-- =============================================================================
-- SICI · Clasificación del histórico para medir rentabilidad (F5) y lo
-- reservado (F7). Escrito a mano. Confirmado por Felipe el 18-10-2026: se
-- cargan los préstamos y los socios, y solo los ven él y Luisa.
--
-- Estas categorías del libro mayor pasan por la caja pero no son costo de
-- ningún proyecto: préstamos, movimientos de socios y traslados entre cuentas.
-- Si se cuentan como costo, la rentabilidad sale peor de lo que es.
--
-- "SOCIOS" aparece además como centro de costo en el libro, y la carga lo dejó
-- como un proyecto de diseño. No lo es: es la cuenta de los socios.
--
-- Se puede ejecutar varias veces sin efecto adicional.
-- =============================================================================
begin;

update public.categoria_costo
   set excluir_de_rentabilidad = true
 where nombre in (
   'SOCIOS',
   'PRESTAMO', 'PRESTAMO A SOCIOS', 'PRESTAMO A TERCERO', 'PRESTAMO A TERCEROS', 'PRESTAMOS A TERCEROS',
   'DEVOLUCION PRESTAMO', 'DEVOLUCION PRESTAMO A SOCIO',
   'CREDITO', 'CREDITOS TERCEROS',
   'TRASLADO ENTRE CUENTAS'
 )
   and not excluir_de_rentabilidad;

update public.proyecto
   set unidad = 'administracion', tipo = 'interno'
 where codigo = 'SOCIOS' and tipo <> 'interno';

-- F7 · Préstamos, créditos y la cuenta de los socios: solo los ven los socios
-- y quien tenga el permiso (Luisa). Los traslados entre cuentas no son
-- reservados: no son de nadie, solo mueven la plata de un banco a otro.
update public.categoria_costo
   set reservada = true
 where nombre in (
   'SOCIOS',
   'PRESTAMO', 'PRESTAMO A SOCIOS', 'PRESTAMO A TERCERO', 'PRESTAMO A TERCEROS', 'PRESTAMOS A TERCEROS',
   'DEVOLUCION PRESTAMO', 'DEVOLUCION PRESTAMO A SOCIO',
   'CREDITO', 'CREDITOS TERCEROS'
 )
   and not reservada;

update public.proyecto set reservado = true where codigo = 'SOCIOS' and not reservado;

-- Decisión de Felipe (05-10-2026): lo administrativo se separa a su propio
-- proyecto interno. Pagar la seguridad social o revisar el arriendo de la
-- oficina es gasto de estructura, no costo de un cliente, y en la hoja de
-- seguimiento aparecía como si fuera un proyecto más.
insert into public.proyecto (codigo, nombre, unidad, tipo, estado)
values ('ADMINISTRATIVO', 'Administración y estructura', 'administracion', 'interno', 'activo')
on conflict (codigo) do update
   set unidad = 'administracion', tipo = 'interno'
 where public.proyecto.tipo <> 'interno';

commit;
