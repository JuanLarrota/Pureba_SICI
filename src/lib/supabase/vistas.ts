// Lo que devuelven las vistas y las funciones de la base que escriben frases.
// Los tipos generados (tipos.ts) marcan toda columna de vista como anulable;
// aquí está lo que la base garantiza de verdad, para que la pantalla no tenga
// que dudar de cada campo. Si una vista cambia, cambia aquí también.

export interface VMiDia {
  origen: "diseno" | "obra";
  id: string;
  proyecto_id: string;
  proyecto: string;
  titulo: string;
  estado: string;
  prioridad: string;
  fecha_compromiso: string | null;
  orden: number;
  grupo: string;
  espera_a: string | null;
  frena_a: string | null;
  para_que: string | null;
  lectura: string;
}

export interface VColaRevision {
  tarea_id: string;
  proyecto_id: string;
  proyecto: string;
  titulo: string;
  persona_id: string;
  persona: string;
  prioridad: string;
  fecha_compromiso: string | null;
  revision_pedida_en: string;
  dias_habiles_esperando: number;
  fuera_de_plazo: boolean;
  devoluciones: number;
  lectura: string;
  revisor_id: string | null;   // R3 · a quién se le delegó; vacía, la revisa quien tiene el papel
}

export interface VFaseAvance {
  fase_id: string;
  proyecto_id: string;
  fase: string;
  estado: string;
  tareas: number;
  terminadas: number;
  trabajo_terminado: boolean;
}

export interface VDedicacionPendiente { persona_id: string; fecha: string }

export interface VVentasHoy {
  persona_id: string | null;
  orden: number;
  que: string;
  lead_id: string | null;
  oportunidad_id: string | null;
  cita_id: string | null;
  nombre: string;
  lectura: string;
  urgente: boolean;
}

export interface VEmbudoVentas { linea: string; etapa: string; oportunidades: number; valor: number | string | null; atrasadas: number; dias_promedio: number | null }
export interface VRitmoVentas { lectura: string | null }
export interface VTareaContexto { tarea_id: string; para_que: string | null }

export interface VObraTablero {
  id: string;
  codigo: string;
  nombre: string;
  estado: string;
  unidad: string;
  carpeta_drive: string | null;
  valor_contrato: number | string | null;
  fecha_inicio: string | null;
  fecha_fin_prevista: string | null;
  residente_id: string | null;
  residente: string | null;
  costo_proyectado: number | string;
  pagado: number | string;
  por_pagar: number | string;
  cobrado: number | string;
  gastos_por_aprobar: number;
  valor_por_aprobar: number | string;
  pendientes_abiertos: number;
  pendientes_vencidos: number;
  pendientes_por_verificar: number;
  dias_sin_bitacora: number;
  ultima_bitacora: string | null;
  adicionales_pendientes: number;
  ultimo_gasto: string | null;
  documentos: number;
  pct_contrato: number | null;
  lectura: string;
  alerta: string | null;
}

export interface VBalanceCentroCosto { proyecto_id: string; categoria: string; presupuesto: number | string | null; proyectado: number | string; por_pagar: number | string; excluir_de_rentabilidad: boolean }

export interface VMovimientoVigente {
  id: string;
  proyecto_id: string;
  fecha: string;
  estado: string;
  naturaleza: string;
  valor: number | string;
  tercero_id: string | null;
  tercero_nombre: string | null;
  concepto: string;
  numero_factura: string | null;
  aprobacion: string;
  registrado_por: string | null;
  registrado_en: string;
}

export interface VObraPorPagar {
  raiz_id: string;
  proyecto_id: string;
  centro_costo_id: string;
  categoria: string;
  tercero: string | null;
  concepto: string;
  fecha: string;
  aprobacion: string;
  numero_factura: string | null;
  facturado: boolean;
  total: number | string;
  pagado: number | string;
  por_pagar: number | string;
  fecha_prevista: string;
}

export interface VObraFlujoMes { proyecto_id: string; mes: string; pagado: number | string; pagos: number; cobrado: number | string }
export interface VBitacoraFaltante { proyecto_id: string; fecha: string }

/** Lo que propone tareas_tipicas al abrir una fase. */
export interface TareaTipica {
  plantilla_tarea_id: string;
  orden: number;
  titulo: string;
  espacio: string | null;
  proposito: string;
  prioridad: string;
  fecha_sugerida: string | null;
  depende_de: string | null;
  dias_estimados: number | null;
  por_espacio: boolean;
}

/** Lo que falta para cerrar una fase, contado por la base. */
export interface Falta { orden: number; que: string; listo: boolean; bloquea: boolean; detalle: string }

/** Un indicador de impacto, con su frase. */
export interface Indicador { orden: number; indicador: string; titulo: string; frase: string; suficiente: boolean }
export interface IndicadorDetalle { proyecto?: string; titulo: string; hecho: string | boolean; a_favor: boolean; excluida: boolean }
