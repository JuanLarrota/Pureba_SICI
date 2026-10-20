// Cómo se lee cada código de la base. Los códigos los define la base; aquí solo
// está la palabra que ve la persona.

export type Diccionario = Record<string, string>;

export const ESTADO: Diccionario = { asignada: "Por empezar", en_curso: "En curso", en_revision: "En revisión", con_observaciones: "Devuelta", terminada: "Terminada" };
export const PASTILLA: Diccionario = { asignada: "n", en_curso: "t", en_revision: "a", con_observaciones: "c", terminada: "o" };
export const ROL: Diccionario = { socio: "Socio", director: "Dirección", arquitecto: "Arquitecto", director_proyecto: "Director de proyecto", practicante: "Practicante",
  residente: "Residente", mercadeo: "Mercadeo", financiero: "Financiero" };
export const UNIDAD: Diccionario = { diseno_arquitectonico: "Diseño arquitectónico", interiorismo: "Interiorismo", consultoria: "Consultoría", obra_propia: "Obra propia",
  obra_colega: "Obra de un colega", peritaje: "Peritaje", administracion: "Administración" };
export const FASE: Record<string, [string, string]> = { pendiente: ["Por abrir", "n"], en_curso: ["En curso", "a"], en_revision: ["En revisión", "a"], cerrada: ["Cerrada", "o"] };
export const PRIORIDAD: Diccionario = { normal: "Normal", alta: "Alta", bloqueante: "Frena a otros" };
/** Las columnas del tablero de un proyecto, en orden. */
export const COLUMNAS: [string, string][] = [["asignada", "Por empezar"], ["en_curso", "En curso"], ["en_revision", "En revisión"], ["con_observaciones", "Devueltas"], ["terminada", "Terminadas"]];
/** Una persona puede tener más de un papel en el mismo proyecto (produce y también revisa). */
export const PAPELES: [string, string][] = [["produce", "Produce"], ["revisa", "Revisa"], ["dirige", "Dirige"]];

// Ventas
export const ETAPA: Diccionario = { cita_viabilidad: "Cita de viabilidad", presupuesto_detallado: "Cotización en preparación", cotizacion_enviada: "Cotización presentada",
  negociacion: "Contrato y anticipo", ganada: "Ganada", perdida: "Perdida" };
export const ABIERTAS = ["cita_viabilidad", "presupuesto_detallado", "cotizacion_enviada", "negociacion"];
export const LINEA: Diccionario = { diseno: "Diseño e interiorismo", obra: "Obra", peritaje: "Peritajes" };
export const lineaDe = (u?: string | null) => (["obra_propia", "obra_colega"].includes(u || "") ? "obra" : u === "peritaje" ? "peritaje" : "diseno");
export const CANAL: Diccionario = { google_ads: "Google Ads", meta_ads: "Meta (Instagram y Facebook)", instagram_organico: "Instagram, sin pauta", referido: "Lo refirió alguien",
  cliente_recurrente: "Ya era cliente", web_organico: "La página web", asistente_ia: "Le preguntó a una IA", whatsapp_directo: "Escribió directo al WhatsApp",
  youtube: "YouTube", linkedin: "LinkedIn", otro: "Otro" };
/** Cómo dice el cliente que nos encontró, para leerlo en una frase. */
export const ENCONTRO: Diccionario = { google_ads: "en Google", meta_ads: "en Instagram o Facebook", instagram_organico: "en Instagram", referido: "por una recomendación",
  cliente_recurrente: "porque ya era cliente", web_organico: "en la página web", asistente_ia: "preguntándole a una IA", whatsapp_directo: "por WhatsApp",
  youtube: "en YouTube", linkedin: "en LinkedIn", otro: "por otro medio" };
export const MOTIVO: Diccionario = { precio: "El precio", tiempo: "El tiempo", competencia: "Se fue con otro", desaparecio: "Dejó de responder", sin_capacidad_pago: "No tiene cómo pagarlo",
  no_calificado: "No era para nosotros", aplazado: "Lo aplazó", otro: "Otro motivo" };
export const RECURSO: Diccionario = { inmediato: "Ya lo tiene", "0_3_meses": "En menos de tres meses", "3_12_meses": "Entre tres meses y un año", mas_12_meses: "En más de un año", no_sabe: "No sabe todavía" };
export const PROPOSITO: Diccionario = { vivienda: "Para vivir", inversion: "Para invertir o arrendar", mixto: "Las dos cosas", comercial: "Un negocio" };
export const LOTE: Diccionario = { si: "Sí", en_proceso: "Lo está comprando", no: "No" };
export const TIPO_CITA: Diccionario = { viabilidad: "Cita de viabilidad", presentacion: "Presentación de la cotización", seguimiento: "Reunión" };
export const ESTADO_CITA: Diccionario = { agendada: "Agendada", realizada: "Hecha", no_show: "No llegó", reprogramada: "Movida", cancelada: "Cancelada" };
export const ESTADO_COT: Diccionario = { borrador: "Borrador", emitida: "Enviada", aceptada: "Aceptada", rechazada: "Rechazada", vencida: "Vencida", reemplazada: "Reemplazada" };
export const ESTADO_LEAD: Diccionario = { nuevo: "Sin primer contacto", contactado: "Contactado", calificado: "Calificado", nutricion: "En nutrición", descartado: "Descartado" };

// Obra
export const SECCION_OBRA: [string, string][] = [["resumen", "Resumen"], ["gastos", "Gastos y facturas"], ["flujo", "Flujo de caja"], ["documentos", "Documentos"], ["pendientes", "Pendientes"], ["sitio", "Registro en sitio"]];
export const ESTADO_DINERO: Diccionario = { compromiso: "Comprometido", causacion: "Facturado, por pagar", pago: "Pagado" };
export const MEDIO: Diccionario = { banco: "Transferencia o consignación", efectivo: "Efectivo", tarjeta: "Tarjeta", credito: "Crédito" };
export const TIPO_DOC: Diccionario = { contrato: "Contrato", presupuesto: "Presupuesto", planos: "Planos", licencia: "Licencia", poliza: "Póliza", acta: "Acta", factura: "Factura", informe: "Informe", otro: "Otro" };
export const TIPO_PEND: Diccionario = { ejecucion: "Ejecución", tramite: "Trámite", revision: "Revisión", compra: "Compra" };
export const ESTADO_PEND: Diccionario = { abierto: "Abierto", en_ejecucion: "En ejecución", por_verificar: "Hecho, falta verificar", cerrado: "Cerrado", descartado: "Descartado" };
export const CLIMA = ["Soleado", "Nublado", "Lluvia en la mañana", "Lluvia en la tarde", "Lluvia todo el día"];

// Cierre de fase y flujo
export const PUNTO: Diccionario = { casilla: "Se marca", opcion: "Se escoge una opción", numero: "Un número", fecha: "Una fecha", enlace: "Un enlace" };
export const RESPONDE: Diccionario = { dirige: "Quien dirige el proyecto", revisa: "Quien revisa", produce: "Quien produce" };
export const PAPEL: Diccionario = { dirige: "Dirige", produce: "Produce en", revisa: "Revisa en", observa: "Observa" };
export const ORDEN_PLANTILLAS = ["Diseño", "Peritaje", "Consultoría", "Obra", "Montaje de interiores", "Interno"];
