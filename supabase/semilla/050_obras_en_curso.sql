-- =============================================================================
-- SICI · Las obras que están en construcción (escrito a mano, 18-10-2026)
--
-- El libro mayor no dice qué obra sigue viva: el histórico entra todo como
-- terminado. Estas cinco tienen pagos en los 60 días anteriores al corte del
-- libro (13 de octubre de 2026); las demás obras pagaron por última vez en
-- marzo de 2026 o antes. Si una ya terminó, dirección la cambia en la ficha.
--
-- Se puede ejecutar varias veces sin efecto adicional.
-- =============================================================================
begin;

update public.proyecto
   set estado = 'activo'
 where tipo = 'obra'
   and estado = 'terminado'
   and codigo in ('OBRA NIRVANA', 'OBRA CALI', 'OBRA KOLIBRI', 'BODEGA TERRANO', 'BODEGA SAKER');

commit;
