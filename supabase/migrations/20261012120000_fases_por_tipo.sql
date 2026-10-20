-- =============================================================================
-- SICI · Módulo de arquitectura y diseño · etapa 2 · 1 de 2
-- Fases por tipo de proyecto y rol de director de proyectos de construcción
--
-- Decisión de Felipe del 12 de octubre de 2026: los peritajes, las consultorías
-- y las obras entran como proyectos, cada tipo con sus fases propias.
--
--   Peritaje y consultoría: levantamiento, informe, presupuesto, entrega del
--                           expediente.
--   Obra:                   preconstrucción, ejecución, cierre.
--
-- 'presupuesto' y 'cierre' ya existían. Aquí solo se agregan las que faltan.
--
-- Va en un archivo aparte a propósito: Postgres no deja usar un valor nuevo de
-- una lista en la misma transacción que lo crea. Por eso las plantillas que
-- usan estas fases se cargan después, desde supabase/semilla/040_plantillas.sql.
--
-- Agregar una fase más adelante es otra línea como estas en una migración nueva.
-- Idempotente.
-- =============================================================================

alter type public.fase_proyecto add value if not exists 'levantamiento';
alter type public.fase_proyecto add value if not exists 'informe';
alter type public.fase_proyecto add value if not exists 'entrega_expediente';
alter type public.fase_proyecto add value if not exists 'preconstruccion';
alter type public.fase_proyecto add value if not exists 'ejecucion';

-- Director de proyectos de construcción (Felipe, 12-10-2026). Hoy es un
-- ingeniero civil; la profesión se escoge aparte, en la ficha de la persona.
alter type public.rol_persona add value if not exists 'director_proyecto';
