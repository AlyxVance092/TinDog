-- =====================================================================
-- respond_breeding_request() + cancel_breeding_request() - v1
-- Se aplica sobre swipe_v1 (usa pair_check, create_match y el mismo lock por par que swipe()).
-- SIN PROBAR: usa dog_dating_respond_tests.sql.
--
-- Estados de una solicitud: pending -> accepted | declined | expired | cancelled
--   * accepted : el dueño del perro DESTINATARIO acepta (revalidando todo en ese momento)
--   * declined : el destinatario rechaza (el solicitante NO recibe push; ve el estado al abrir la app)
--   * expired  : venció expires_at (se marca al intentar responder; el cron de limpieza vendra aparte)
--   * cancelled: el solicitante la retira, o quedó invalida (el solicitante dejó de tener 'breeding')
-- Rechazar o cancelar es DEFINITIVO: UNIQUE(requester, target) y swipes impiden volver a solicitar.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- respond_breeding_request(request_id, accept)
--   { ok: true,  result: 'declined' }
--   { ok: true,  result: 'match', match_id, conversation_id, request_id }
--   { ok: false, error: 'request_not_found' | 'request_not_pending' (+status) | 'request_expired'
--                     | 'request_cancelled' | 'my_dog_paused' | 'my_health_required' | 'not_eligible' }
--   Excepcion: not_authenticated.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.respond_breeding_request(p_request_id uuid, p_accept boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_req public.breeding_requests;
  v_target public.dogs;
  v_mode public.dog_intention;
  v_reason text;
  v_match record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000'; END IF;

  SELECT * INTO v_req FROM public.breeding_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- solo el dueño del perro DESTINATARIO puede responder (si no, no se revela que existe)
  SELECT * INTO v_target FROM public.dogs
   WHERE id = v_req.target_dog_id AND owner_id = v_uid AND NOT is_deleted;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  -- mismo lock por par que swipe(): evita carreras con un like inverso simultaneo
  PERFORM pg_advisory_xact_lock(hashtextextended(
            least(v_req.requester_dog_id::text, v_req.target_dog_id::text)
            || greatest(v_req.requester_dog_id::text, v_req.target_dog_id::text), 0));
  SELECT * INTO v_req FROM public.breeding_requests WHERE id = p_request_id FOR UPDATE;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_pending', 'status', v_req.status);
  END IF;

  IF v_req.expires_at <= now() THEN
    UPDATE public.breeding_requests SET status = 'expired', responded_at = now() WHERE id = v_req.id;
    RETURN jsonb_build_object('ok', false, 'error', 'request_expired');
  END IF;

  -- ---------- RECHAZAR ----------
  IF NOT p_accept THEN
    UPDATE public.breeding_requests SET status = 'declined', responded_at = now() WHERE id = v_req.id;
    -- el perro destinatario "descarta" al solicitante: ninguno vuelve a salir en el feed del otro
    INSERT INTO public.swipes (swiper_dog_id, target_dog_id, action, mode)
    VALUES (v_req.target_dog_id, v_req.requester_dog_id, 'pass', 'breeding')
    ON CONFLICT DO NOTHING;
    UPDATE public.notifications SET read_at = COALESCE(read_at, now())
     WHERE user_id = v_uid AND type = 'breeding_request' AND payload->>'request_id' = v_req.id::text;
    RETURN jsonb_build_object('ok', true, 'result', 'declined');
  END IF;

  -- ---------- ACEPTAR: se revalida TODO con la misma logica que el feed y swipe() ----------
  IF NOT v_target.is_visible THEN
    RETURN jsonb_build_object('ok', false, 'error', 'my_dog_paused');
  END IF;

  SELECT pc.o_mode, pc.o_reason INTO v_mode, v_reason
    FROM private.pair_check(v_req.requester_dog_id, v_req.target_dog_id) pc;

  -- el solicitante ya no cumple para cruza (cambio de intencion, perro borrado, bloqueo...): solicitud invalida
  IF v_mode IS DISTINCT FROM 'breeding' THEN
    UPDATE public.breeding_requests SET status = 'cancelled', responded_at = now() WHERE id = v_req.id;
    RETURN jsonb_build_object('ok', false, 'error', 'request_cancelled');
  END IF;

  IF v_reason IS NOT NULL THEN
    -- solo se revela lo que es MIO (mi salud); el resto queda como generico. La solicitud sigue pendiente.
    IF v_reason = 'health_required' AND NOT private.health_ok(v_target.id, 'breeding') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'my_health_required');
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'not_eligible');
  END IF;

  UPDATE public.breeding_requests SET status = 'accepted', responded_at = now() WHERE id = v_req.id;

  -- registra el like del destinatario (excluye al solicitante de su feed)
  INSERT INTO public.swipes (swiper_dog_id, target_dog_id, action, mode)
  VALUES (v_req.target_dog_id, v_req.requester_dog_id, 'like', 'breeding')
  ON CONFLICT DO NOTHING;

  SELECT * INTO v_match FROM private.create_match(v_req.requester_dog_id, v_req.target_dog_id, 'breeding', v_req.id);

  UPDATE public.notifications SET read_at = COALESCE(read_at, now())
   WHERE user_id = v_uid AND type = 'breeding_request' AND payload->>'request_id' = v_req.id::text;

  INSERT INTO public.notifications (user_id, type, priority, payload)
  VALUES (v_req.requester_user_id, 'breeding_accepted', 'high',
          jsonb_build_object('request_id', v_req.id, 'match_id', v_match.o_match_id,
                             'conversation_id', v_match.o_conversation_id,
                             'accepted_by_dog_id', v_req.target_dog_id));

  RETURN jsonb_build_object('ok', true, 'result', 'match', 'request_id', v_req.id,
                            'match_id', v_match.o_match_id, 'conversation_id', v_match.o_conversation_id);
END $$;

-- ---------------------------------------------------------------------
-- cancel_breeding_request(request_id): el SOLICITANTE retira una solicitud pendiente
--   { ok: true,  result: 'cancelled' }
--   { ok: false, error: 'request_not_found' | 'request_not_pending' (+status) }
--   No devuelve el cupo diario (evita ciclos de pedir/cancelar) y es definitiva.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_breeding_request(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_req public.breeding_requests;
  v_target_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000'; END IF;

  SELECT * INTO v_req FROM public.breeding_requests
   WHERE id = p_request_id AND requester_user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
            least(v_req.requester_dog_id::text, v_req.target_dog_id::text)
            || greatest(v_req.requester_dog_id::text, v_req.target_dog_id::text), 0));
  SELECT * INTO v_req FROM public.breeding_requests WHERE id = p_request_id FOR UPDATE;

  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_pending', 'status', v_req.status);
  END IF;

  UPDATE public.breeding_requests SET status = 'cancelled', responded_at = now() WHERE id = v_req.id;

  -- si el destinatario aun no habia visto el aviso, se retira de su bandeja
  SELECT d.owner_id INTO v_target_owner FROM public.dogs d WHERE d.id = v_req.target_dog_id;
  DELETE FROM public.notifications
   WHERE user_id = v_target_owner AND type = 'breeding_request'
     AND payload->>'request_id' = v_req.id::text AND read_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'result', 'cancelled');
END $$;

-- ---------------------------------------------------------------------
-- PERMISOS
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.respond_breeding_request(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.respond_breeding_request(uuid, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_breeding_request(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.cancel_breeding_request(uuid) TO authenticated;

-- NOTA para la bandeja del destinatario: las solicitudes se leen con SELECT sobre breeding_requests
-- (la RLS ya lo permite) y el perro solicitante es legible por la relacion de solicitud
-- (has_relation_with_dog). Si prefieres una sola llamada con tarjeta, salud y "¿puedo aceptar?",
-- el siguiente paso seria get_breeding_inbox().

COMMIT;
