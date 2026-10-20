// Generado por scripts/base/generar_tipos.py desde las migraciones de supabase/migrations.
// No se edita a mano: se vuelve a generar cuando cambia la base.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  __InternalSupabase: { PostgrestVersion: "12" }
  public: {
    Tables: {
      acceso_proyecto: {
        Row: {
          persona_id: string
          proyecto_id: string
          nivel: Database["public"]["Enums"]["nivel_acceso"]
          otorgado_en: string
          papel: Database["public"]["Enums"]["papel_proyecto"]
        }
        Insert: {
          persona_id: string
          proyecto_id: string
          nivel?: Database["public"]["Enums"]["nivel_acceso"]
          otorgado_en?: string
          papel: Database["public"]["Enums"]["papel_proyecto"]
        }
        Update: {
          persona_id?: string
          proyecto_id?: string
          nivel?: Database["public"]["Enums"]["nivel_acceso"]
          otorgado_en?: string
          papel?: Database["public"]["Enums"]["papel_proyecto"]
        }
        Relationships: [
          { foreignKeyName: "acceso_proyecto_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "acceso_proyecto_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      acta: {
        Row: {
          id: string
          proyecto_id: string
          tipo: Database["public"]["Enums"]["tipo_acta"]
          numero: string
          tercero_id: string | null
          corte_desde: string | null
          corte_hasta: string | null
          valor: number
          valor_retenido: number
          emitida_en: string
          vence_en: string | null
          aprobada_por: string | null
          anulada: boolean
          motivo_anulacion: string | null
          observaciones: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          tipo: Database["public"]["Enums"]["tipo_acta"]
          numero: string
          tercero_id?: string | null
          corte_desde?: string | null
          corte_hasta?: string | null
          valor: number
          valor_retenido?: number
          emitida_en?: string
          vence_en?: string | null
          aprobada_por?: string | null
          anulada?: boolean
          motivo_anulacion?: string | null
          observaciones?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          tipo?: Database["public"]["Enums"]["tipo_acta"]
          numero?: string
          tercero_id?: string | null
          corte_desde?: string | null
          corte_hasta?: string | null
          valor?: number
          valor_retenido?: number
          emitida_en?: string
          vence_en?: string | null
          aprobada_por?: string | null
          anulada?: boolean
          motivo_anulacion?: string | null
          observaciones?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "acta_aprobada_por_fkey"; columns: ["aprobada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "acta_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "acta_tercero_id_fkey"; columns: ["tercero_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      acta_item: {
        Row: {
          id: string
          acta_id: string
          item_id: string | null
          adicional_id: string | null
          descripcion: string | null
          unidad: string | null
          cantidad: number
          valor_unitario: number
          valor: number | null
        }
        Insert: {
          id?: string
          acta_id: string
          item_id?: string | null
          adicional_id?: string | null
          descripcion?: string | null
          unidad?: string | null
          cantidad: number
          valor_unitario: number
          valor?: never
        }
        Update: {
          id?: string
          acta_id?: string
          item_id?: string | null
          adicional_id?: string | null
          descripcion?: string | null
          unidad?: string | null
          cantidad?: number
          valor_unitario?: number
          valor?: never
        }
        Relationships: [
          { foreignKeyName: "acta_item_acta_id_fkey"; columns: ["acta_id"]; isOneToOne: false; referencedRelation: "acta"; referencedColumns: ["id"] },
          { foreignKeyName: "acta_item_adicional_id_fkey"; columns: ["adicional_id"]; isOneToOne: false; referencedRelation: "adicional"; referencedColumns: ["id"] },
          { foreignKeyName: "acta_item_item_id_fkey"; columns: ["item_id"]; isOneToOne: false; referencedRelation: "item_presupuesto"; referencedColumns: ["id"] }
        ]
      }
      actividad_cronograma: {
        Row: {
          id: string
          presupuesto_id: string
          capitulo_id: string | null
          nombre: string
          inicio: string
          fin: string
          predecesora_id: string | null
          pct_avance: number
          orden: number
        }
        Insert: {
          id?: string
          presupuesto_id: string
          capitulo_id?: string | null
          nombre: string
          inicio: string
          fin: string
          predecesora_id?: string | null
          pct_avance?: number
          orden?: number
        }
        Update: {
          id?: string
          presupuesto_id?: string
          capitulo_id?: string | null
          nombre?: string
          inicio?: string
          fin?: string
          predecesora_id?: string | null
          pct_avance?: number
          orden?: number
        }
        Relationships: [
          { foreignKeyName: "actividad_cronograma_capitulo_id_fkey"; columns: ["capitulo_id"]; isOneToOne: false; referencedRelation: "capitulo"; referencedColumns: ["id"] },
          { foreignKeyName: "actividad_cronograma_predecesora_id_fkey"; columns: ["predecesora_id"]; isOneToOne: false; referencedRelation: "actividad_cronograma"; referencedColumns: ["id"] },
          { foreignKeyName: "actividad_cronograma_presupuesto_id_fkey"; columns: ["presupuesto_id"]; isOneToOne: false; referencedRelation: "presupuesto"; referencedColumns: ["id"] }
        ]
      }
      adicional: {
        Row: {
          id: string
          proyecto_id: string
          codigo: string
          capitulo_nombre: string | null
          descripcion: string
          unidad: string | null
          cantidad: number
          valor_unitario: number
          valor: number | null
          asume: string
          aprobacion: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por_texto: string | null
          aprobado_por_id: string | null
          aprobado_en: string | null
          medio_aprobacion: string | null
          acta_referencia: string | null
          reemplaza_item_id: string | null
          elemento_id: string | null
          cambio_obra_id: string | null
          motivo: string | null
          creado_en: string
          retirado_en: string | null
          retirado_por: string | null
          retirado_motivo: string | null
        }
        Insert: {
          id?: string
          proyecto_id: string
          codigo: string
          capitulo_nombre?: string | null
          descripcion: string
          unidad?: string | null
          cantidad?: number
          valor_unitario?: number
          valor?: never
          asume?: string
          aprobacion?: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por_texto?: string | null
          aprobado_por_id?: string | null
          aprobado_en?: string | null
          medio_aprobacion?: string | null
          acta_referencia?: string | null
          reemplaza_item_id?: string | null
          elemento_id?: string | null
          cambio_obra_id?: string | null
          motivo?: string | null
          creado_en?: string
          retirado_en?: string | null
          retirado_por?: string | null
          retirado_motivo?: string | null
        }
        Update: {
          id?: string
          proyecto_id?: string
          codigo?: string
          capitulo_nombre?: string | null
          descripcion?: string
          unidad?: string | null
          cantidad?: number
          valor_unitario?: number
          valor?: never
          asume?: string
          aprobacion?: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por_texto?: string | null
          aprobado_por_id?: string | null
          aprobado_en?: string | null
          medio_aprobacion?: string | null
          acta_referencia?: string | null
          reemplaza_item_id?: string | null
          elemento_id?: string | null
          cambio_obra_id?: string | null
          motivo?: string | null
          creado_en?: string
          retirado_en?: string | null
          retirado_por?: string | null
          retirado_motivo?: string | null
        }
        Relationships: [
          { foreignKeyName: "adicional_aprobado_por_id_fkey"; columns: ["aprobado_por_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "adicional_cambio_obra_id_fkey"; columns: ["cambio_obra_id"]; isOneToOne: false; referencedRelation: "cambio_obra"; referencedColumns: ["id"] },
          { foreignKeyName: "adicional_elemento_id_fkey"; columns: ["elemento_id"]; isOneToOne: false; referencedRelation: "elemento_diseno"; referencedColumns: ["id"] },
          { foreignKeyName: "adicional_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "adicional_reemplaza_item_id_fkey"; columns: ["reemplaza_item_id"]; isOneToOne: false; referencedRelation: "item_presupuesto"; referencedColumns: ["id"] },
          { foreignKeyName: "adicional_retirado_por_fkey"; columns: ["retirado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      alerta: {
        Row: {
          id: string
          tipo: string
          clave: string | null
          severidad: Database["public"]["Enums"]["severidad"]
          proyecto_id: string | null
          titulo: string
          detalle: string | null
          destinatarios: string[]
          canales: Database["public"]["Enums"]["canal_aviso"][]
          resuelta: boolean
          resuelta_por: string | null
          resuelta_en: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          tipo: string
          clave?: string | null
          severidad?: Database["public"]["Enums"]["severidad"]
          proyecto_id?: string | null
          titulo: string
          detalle?: string | null
          destinatarios: string[]
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          resuelta?: boolean
          resuelta_por?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          tipo?: string
          clave?: string | null
          severidad?: Database["public"]["Enums"]["severidad"]
          proyecto_id?: string | null
          titulo?: string
          detalle?: string | null
          destinatarios?: string[]
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          resuelta?: boolean
          resuelta_por?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "alerta_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "alerta_resuelta_por_fkey"; columns: ["resuelta_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      aprobacion_cliente: {
        Row: {
          id: string
          adicional_id: string
          persona_id: string
          decision: Database["public"]["Enums"]["estado_aprobacion"]
          comentario: string | null
          decidido_en: string
        }
        Insert: {
          id?: string
          adicional_id: string
          persona_id: string
          decision: Database["public"]["Enums"]["estado_aprobacion"]
          comentario?: string | null
          decidido_en?: string
        }
        Update: {
          id?: string
          adicional_id?: string
          persona_id?: string
          decision?: Database["public"]["Enums"]["estado_aprobacion"]
          comentario?: string | null
          decidido_en?: string
        }
        Relationships: [
          { foreignKeyName: "aprobacion_cliente_adicional_id_fkey"; columns: ["adicional_id"]; isOneToOne: false; referencedRelation: "adicional"; referencedColumns: ["id"] },
          { foreignKeyName: "aprobacion_cliente_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      apu: {
        Row: {
          id: string
          codigo: string
          descripcion: string
          unidad: string
          notas: string | null
          creado_en: string
          actualizado_en: string
        }
        Insert: {
          id?: string
          codigo: string
          descripcion: string
          unidad: string
          notas?: string | null
          creado_en?: string
          actualizado_en?: string
        }
        Update: {
          id?: string
          codigo?: string
          descripcion?: string
          unidad?: string
          notas?: string | null
          creado_en?: string
          actualizado_en?: string
        }
        Relationships: []
      }
      apu_componente: {
        Row: {
          id: string
          apu_id: string
          insumo_id: string
          cantidad: number
          desperdicio: number
        }
        Insert: {
          id?: string
          apu_id: string
          insumo_id: string
          cantidad: number
          desperdicio?: number
        }
        Update: {
          id?: string
          apu_id?: string
          insumo_id?: string
          cantidad?: number
          desperdicio?: number
        }
        Relationships: [
          { foreignKeyName: "apu_componente_apu_id_fkey"; columns: ["apu_id"]; isOneToOne: false; referencedRelation: "apu"; referencedColumns: ["id"] },
          { foreignKeyName: "apu_componente_insumo_id_fkey"; columns: ["insumo_id"]; isOneToOne: false; referencedRelation: "insumo"; referencedColumns: ["id"] }
        ]
      }
      aviso: {
        Row: {
          id: string
          alerta_id: string
          persona_id: string
          canal: Database["public"]["Enums"]["canal_aviso"]
          estado: Database["public"]["Enums"]["estado_aviso"]
          intentos: number
          enviado_en: string | null
          error: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          alerta_id: string
          persona_id: string
          canal: Database["public"]["Enums"]["canal_aviso"]
          estado?: Database["public"]["Enums"]["estado_aviso"]
          intentos?: number
          enviado_en?: string | null
          error?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          alerta_id?: string
          persona_id?: string
          canal?: Database["public"]["Enums"]["canal_aviso"]
          estado?: Database["public"]["Enums"]["estado_aviso"]
          intentos?: number
          enviado_en?: string | null
          error?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "aviso_alerta_id_fkey"; columns: ["alerta_id"]; isOneToOne: false; referencedRelation: "alerta"; referencedColumns: ["id"] },
          { foreignKeyName: "aviso_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      bitacora: {
        Row: {
          id: string
          proyecto_id: string
          fecha: string
          personal_sitio: number | null
          frente_trabajo: string | null
          avance: string | null
          novedad: string | null
          clima: string | null
          registrado_por: string
          registrado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          fecha: string
          personal_sitio?: number | null
          frente_trabajo?: string | null
          avance?: string | null
          novedad?: string | null
          clima?: string | null
          registrado_por: string
          registrado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          fecha?: string
          personal_sitio?: number | null
          frente_trabajo?: string | null
          avance?: string | null
          novedad?: string | null
          clima?: string | null
          registrado_por?: string
          registrado_en?: string
        }
        Relationships: [
          { foreignKeyName: "bitacora_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "bitacora_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      bitacora_cuadrilla: {
        Row: {
          id: string
          bitacora_id: string
          contratista_id: string | null
          cuadrilla: string | null
          personas: number | null
          actividad: string
          capitulo_id: string | null
        }
        Insert: {
          id?: string
          bitacora_id: string
          contratista_id?: string | null
          cuadrilla?: string | null
          personas?: number | null
          actividad: string
          capitulo_id?: string | null
        }
        Update: {
          id?: string
          bitacora_id?: string
          contratista_id?: string | null
          cuadrilla?: string | null
          personas?: number | null
          actividad?: string
          capitulo_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "bitacora_cuadrilla_bitacora_id_fkey"; columns: ["bitacora_id"]; isOneToOne: false; referencedRelation: "bitacora"; referencedColumns: ["id"] },
          { foreignKeyName: "bitacora_cuadrilla_capitulo_id_fkey"; columns: ["capitulo_id"]; isOneToOne: false; referencedRelation: "capitulo"; referencedColumns: ["id"] },
          { foreignKeyName: "bitacora_cuadrilla_contratista_id_fkey"; columns: ["contratista_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      calificacion: {
        Row: {
          id: string
          oportunidad_id: string
          tiene_lote: string | null
          conoce_techo: boolean | null
          techo_presupuestal: number | null
          recurso_disponible: string | null
          proposito: string | null
          primera_cotizacion: boolean | null
          decisores: number | null
          area_inicial_m2: number | null
          area_reencuadrada_m2: number | null
          reaccion_costo: string | null
          registrada_por: string | null
          registrada_en: string
          decisor_presente: boolean | null
          cita_id: string | null
        }
        Insert: {
          id?: string
          oportunidad_id: string
          tiene_lote?: string | null
          conoce_techo?: boolean | null
          techo_presupuestal?: number | null
          recurso_disponible?: string | null
          proposito?: string | null
          primera_cotizacion?: boolean | null
          decisores?: number | null
          area_inicial_m2?: number | null
          area_reencuadrada_m2?: number | null
          reaccion_costo?: string | null
          registrada_por?: string | null
          registrada_en?: string
          decisor_presente?: boolean | null
          cita_id?: string | null
        }
        Update: {
          id?: string
          oportunidad_id?: string
          tiene_lote?: string | null
          conoce_techo?: boolean | null
          techo_presupuestal?: number | null
          recurso_disponible?: string | null
          proposito?: string | null
          primera_cotizacion?: boolean | null
          decisores?: number | null
          area_inicial_m2?: number | null
          area_reencuadrada_m2?: number | null
          reaccion_costo?: string | null
          registrada_por?: string | null
          registrada_en?: string
          decisor_presente?: boolean | null
          cita_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "calificacion_cita_id_fkey"; columns: ["cita_id"]; isOneToOne: false; referencedRelation: "cita"; referencedColumns: ["id"] },
          { foreignKeyName: "calificacion_oportunidad_id_fkey"; columns: ["oportunidad_id"]; isOneToOne: true; referencedRelation: "oportunidad"; referencedColumns: ["id"] },
          { foreignKeyName: "calificacion_registrada_por_fkey"; columns: ["registrada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      cambio_obra: {
        Row: {
          id: string
          proyecto_id: string
          fecha: string
          descripcion: string
          motivo: string | null
          decidido_por: string
          altera_diseno: boolean
          reflejado_en_diseno_en: string | null
          reflejado_por: string | null
          genera_adicional: boolean
          creado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          fecha?: string
          descripcion: string
          motivo?: string | null
          decidido_por: string
          altera_diseno?: boolean
          reflejado_en_diseno_en?: string | null
          reflejado_por?: string | null
          genera_adicional?: boolean
          creado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          fecha?: string
          descripcion?: string
          motivo?: string | null
          decidido_por?: string
          altera_diseno?: boolean
          reflejado_en_diseno_en?: string | null
          reflejado_por?: string | null
          genera_adicional?: boolean
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "cambio_obra_decidido_por_fkey"; columns: ["decidido_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "cambio_obra_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "cambio_obra_reflejado_por_fkey"; columns: ["reflejado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      campana: {
        Row: {
          id: string
          nombre: string
          canal: Database["public"]["Enums"]["canal_origen"]
          plataforma: string | null
          id_externo: string | null
          landing: string | null
          experimento_id: string | null
          inicio: string | null
          fin: string | null
          activa: boolean
          creada_en: string
        }
        Insert: {
          id?: string
          nombre: string
          canal: Database["public"]["Enums"]["canal_origen"]
          plataforma?: string | null
          id_externo?: string | null
          landing?: string | null
          experimento_id?: string | null
          inicio?: string | null
          fin?: string | null
          activa?: boolean
          creada_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          canal?: Database["public"]["Enums"]["canal_origen"]
          plataforma?: string | null
          id_externo?: string | null
          landing?: string | null
          experimento_id?: string | null
          inicio?: string | null
          fin?: string | null
          activa?: boolean
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "campana_experimento_id_fkey"; columns: ["experimento_id"]; isOneToOne: false; referencedRelation: "experimento"; referencedColumns: ["id"] }
        ]
      }
      capitulo: {
        Row: {
          id: string
          presupuesto_id: string
          codigo: string
          nombre: string
          orden: number
        }
        Insert: {
          id?: string
          presupuesto_id: string
          codigo: string
          nombre: string
          orden?: number
        }
        Update: {
          id?: string
          presupuesto_id?: string
          codigo?: string
          nombre?: string
          orden?: number
        }
        Relationships: [
          { foreignKeyName: "capitulo_presupuesto_id_fkey"; columns: ["presupuesto_id"]; isOneToOne: false; referencedRelation: "presupuesto"; referencedColumns: ["id"] }
        ]
      }
      categoria_costo: {
        Row: {
          id: number
          nombre: string
          tipo_gasto: string
          es_directo: boolean
          excluir_de_rentabilidad: boolean
          orden: number
          activo: boolean
          reservada: boolean
        }
        Insert: {
          id?: number
          nombre: string
          tipo_gasto: string
          es_directo?: boolean
          excluir_de_rentabilidad?: boolean
          orden?: number
          activo?: boolean
          reservada?: boolean
        }
        Update: {
          id?: number
          nombre?: string
          tipo_gasto?: string
          es_directo?: boolean
          excluir_de_rentabilidad?: boolean
          orden?: number
          activo?: boolean
          reservada?: boolean
        }
        Relationships: []
      }
      centro_costo: {
        Row: {
          id: string
          proyecto_id: string
          categoria_id: number
          presupuesto: number
          activo: boolean
        }
        Insert: {
          id?: string
          proyecto_id: string
          categoria_id: number
          presupuesto?: number
          activo?: boolean
        }
        Update: {
          id?: string
          proyecto_id?: string
          categoria_id?: number
          presupuesto?: number
          activo?: boolean
        }
        Relationships: [
          { foreignKeyName: "centro_costo_categoria_id_fkey"; columns: ["categoria_id"]; isOneToOne: false; referencedRelation: "categoria_costo"; referencedColumns: ["id"] },
          { foreignKeyName: "centro_costo_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      chequeo: {
        Row: {
          id: string
          lista_id: string
          proyecto_id: string
          fase_id: string | null
          radicacion_id: string | null
          reclamacion_id: string | null
          presupuesto_id: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          lista_id: string
          proyecto_id: string
          fase_id?: string | null
          radicacion_id?: string | null
          reclamacion_id?: string | null
          presupuesto_id?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          lista_id?: string
          proyecto_id?: string
          fase_id?: string | null
          radicacion_id?: string | null
          reclamacion_id?: string | null
          presupuesto_id?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "chequeo_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_lista_id_fkey"; columns: ["lista_id"]; isOneToOne: false; referencedRelation: "lista_chequeo"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_presupuesto_id_fkey"; columns: ["presupuesto_id"]; isOneToOne: false; referencedRelation: "presupuesto"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_radicacion_id_fkey"; columns: ["radicacion_id"]; isOneToOne: false; referencedRelation: "radicacion_licencia"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_reclamacion_id_fkey"; columns: ["reclamacion_id"]; isOneToOne: false; referencedRelation: "reclamacion"; referencedColumns: ["id"] }
        ]
      }
      chequeo_respuesta: {
        Row: {
          id: string
          chequeo_id: string
          item_id: string
          cumple: boolean
          nota: string | null
          evidencia_ruta: string | null
          verificado_por: string
          verificado_en: string
          valor: string | null
        }
        Insert: {
          id?: string
          chequeo_id: string
          item_id: string
          cumple: boolean
          nota?: string | null
          evidencia_ruta?: string | null
          verificado_por: string
          verificado_en?: string
          valor?: string | null
        }
        Update: {
          id?: string
          chequeo_id?: string
          item_id?: string
          cumple?: boolean
          nota?: string | null
          evidencia_ruta?: string | null
          verificado_por?: string
          verificado_en?: string
          valor?: string | null
        }
        Relationships: [
          { foreignKeyName: "chequeo_respuesta_chequeo_id_fkey"; columns: ["chequeo_id"]; isOneToOne: false; referencedRelation: "chequeo"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_respuesta_item_id_fkey"; columns: ["item_id"]; isOneToOne: false; referencedRelation: "lista_chequeo_item"; referencedColumns: ["id"] },
          { foreignKeyName: "chequeo_respuesta_verificado_por_fkey"; columns: ["verificado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      cierre_mes: {
        Row: {
          id: string
          periodo: string
          cerrado_por: string
          cerrado_en: string
          reabierto_en: string | null
          reabierto_por: string | null
          motivo_reapertura: string | null
        }
        Insert: {
          id?: string
          periodo: string
          cerrado_por: string
          cerrado_en?: string
          reabierto_en?: string | null
          reabierto_por?: string | null
          motivo_reapertura?: string | null
        }
        Update: {
          id?: string
          periodo?: string
          cerrado_por?: string
          cerrado_en?: string
          reabierto_en?: string | null
          reabierto_por?: string | null
          motivo_reapertura?: string | null
        }
        Relationships: [
          { foreignKeyName: "cierre_mes_cerrado_por_fkey"; columns: ["cerrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "cierre_mes_reabierto_por_fkey"; columns: ["reabierto_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      cita: {
        Row: {
          id: string
          oportunidad_id: string
          programada_para: string
          modalidad: string
          estado: Database["public"]["Enums"]["estado_cita"]
          consentimiento_grabacion: boolean | null
          grabacion_url: string | null
          realizada_en: string | null
          duracion_min: number | null
          reprogramada_a: string | null
          notas: string | null
          creada_en: string
          tipo: string
          transcripcion_url: string | null
        }
        Insert: {
          id?: string
          oportunidad_id: string
          programada_para: string
          modalidad?: string
          estado?: Database["public"]["Enums"]["estado_cita"]
          consentimiento_grabacion?: boolean | null
          grabacion_url?: string | null
          realizada_en?: string | null
          duracion_min?: number | null
          reprogramada_a?: string | null
          notas?: string | null
          creada_en?: string
          tipo?: string
          transcripcion_url?: string | null
        }
        Update: {
          id?: string
          oportunidad_id?: string
          programada_para?: string
          modalidad?: string
          estado?: Database["public"]["Enums"]["estado_cita"]
          consentimiento_grabacion?: boolean | null
          grabacion_url?: string | null
          realizada_en?: string | null
          duracion_min?: number | null
          reprogramada_a?: string | null
          notas?: string | null
          creada_en?: string
          tipo?: string
          transcripcion_url?: string | null
        }
        Relationships: [
          { foreignKeyName: "cita_oportunidad_id_fkey"; columns: ["oportunidad_id"]; isOneToOne: false; referencedRelation: "oportunidad"; referencedColumns: ["id"] },
          { foreignKeyName: "cita_reprogramada_a_fkey"; columns: ["reprogramada_a"]; isOneToOne: false; referencedRelation: "cita"; referencedColumns: ["id"] }
        ]
      }
      cliente: {
        Row: {
          id: string
          nombre: string
          tipo: string
          nit: string | null
          contacto_id: string | null
          telefono: string | null
          correo: string | null
          ciudad: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          nombre: string
          tipo?: string
          nit?: string | null
          contacto_id?: string | null
          telefono?: string | null
          correo?: string | null
          ciudad?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          tipo?: string
          nit?: string | null
          contacto_id?: string | null
          telefono?: string | null
          correo?: string | null
          ciudad?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "cliente_contacto_id_fkey"; columns: ["contacto_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      complementario: {
        Row: {
          id: string
          proyecto_id: string
          especialidad: Database["public"]["Enums"]["especialidad"]
          profesional_id: string | null
          valor_contratado: number | null
          pct_anticipo: number
          fecha_compromiso: string | null
          entregado_en: string | null
          estado: Database["public"]["Enums"]["estado_complementario"]
          notas: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          especialidad: Database["public"]["Enums"]["especialidad"]
          profesional_id?: string | null
          valor_contratado?: number | null
          pct_anticipo?: number
          fecha_compromiso?: string | null
          entregado_en?: string | null
          estado?: Database["public"]["Enums"]["estado_complementario"]
          notas?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          especialidad?: Database["public"]["Enums"]["especialidad"]
          profesional_id?: string | null
          valor_contratado?: number | null
          pct_anticipo?: number
          fecha_compromiso?: string | null
          entregado_en?: string | null
          estado?: Database["public"]["Enums"]["estado_complementario"]
          notas?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "complementario_profesional_id_fkey"; columns: ["profesional_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "complementario_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      contacto_lead: {
        Row: {
          id: string
          lead_id: string
          fecha: string
          medio: Database["public"]["Enums"]["medio_contacto"]
          direccion: string
          respondio: boolean
          nota: string | null
          registrado_por: string | null
        }
        Insert: {
          id?: string
          lead_id: string
          fecha?: string
          medio: Database["public"]["Enums"]["medio_contacto"]
          direccion: string
          respondio?: boolean
          nota?: string | null
          registrado_por?: string | null
        }
        Update: {
          id?: string
          lead_id?: string
          fecha?: string
          medio?: Database["public"]["Enums"]["medio_contacto"]
          direccion?: string
          respondio?: boolean
          nota?: string | null
          registrado_por?: string | null
        }
        Relationships: [
          { foreignKeyName: "contacto_lead_lead_id_fkey"; columns: ["lead_id"]; isOneToOne: false; referencedRelation: "lead"; referencedColumns: ["id"] },
          { foreignKeyName: "contacto_lead_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      cotizacion: {
        Row: {
          id: string
          oportunidad_id: string | null
          proyecto_id: string | null
          numero: string
          version: number
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          unidad: Database["public"]["Enums"]["unidad_negocio"] | null
          valor: number
          costo_estimado: number | null
          horas_estimadas: number | null
          estado: Database["public"]["Enums"]["estado_cotizacion"]
          emitida_en: string | null
          vence_en: string | null
          respondida_en: string | null
          margen_autorizado_por: string | null
          margen_autorizado_en: string | null
          ruta_documento: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          oportunidad_id?: string | null
          proyecto_id?: string | null
          numero: string
          version?: number
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          unidad?: Database["public"]["Enums"]["unidad_negocio"] | null
          valor: number
          costo_estimado?: number | null
          horas_estimadas?: number | null
          estado?: Database["public"]["Enums"]["estado_cotizacion"]
          emitida_en?: string | null
          vence_en?: string | null
          respondida_en?: string | null
          margen_autorizado_por?: string | null
          margen_autorizado_en?: string | null
          ruta_documento?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          oportunidad_id?: string | null
          proyecto_id?: string | null
          numero?: string
          version?: number
          tipo?: Database["public"]["Enums"]["tipo_proyecto"]
          unidad?: Database["public"]["Enums"]["unidad_negocio"] | null
          valor?: number
          costo_estimado?: number | null
          horas_estimadas?: number | null
          estado?: Database["public"]["Enums"]["estado_cotizacion"]
          emitida_en?: string | null
          vence_en?: string | null
          respondida_en?: string | null
          margen_autorizado_por?: string | null
          margen_autorizado_en?: string | null
          ruta_documento?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "cotizacion_margen_autorizado_por_fkey"; columns: ["margen_autorizado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "cotizacion_oportunidad_id_fkey"; columns: ["oportunidad_id"]; isOneToOne: false; referencedRelation: "oportunidad"; referencedColumns: ["id"] },
          { foreignKeyName: "cotizacion_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      cuenta: {
        Row: {
          id: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_cuenta"]
          banco: string | null
          ultimos4: string | null
          activa: boolean
          creada_en: string
        }
        Insert: {
          id?: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_cuenta"]
          banco?: string | null
          ultimos4?: string | null
          activa?: boolean
          creada_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          tipo?: Database["public"]["Enums"]["tipo_cuenta"]
          banco?: string | null
          ultimos4?: string | null
          activa?: boolean
          creada_en?: string
        }
        Relationships: []
      }
      dedicacion: {
        Row: {
          id: string
          persona_id: string
          fecha: string
          bloque: Database["public"]["Enums"]["bloque_dia"]
          tipo: string
          proyecto_id: string | null
          fase_id: string | null
          tarea_id: string | null
          horas: number
          registrada_en: string
        }
        Insert: {
          id?: string
          persona_id: string
          fecha: string
          bloque: Database["public"]["Enums"]["bloque_dia"]
          tipo?: string
          proyecto_id?: string | null
          fase_id?: string | null
          tarea_id?: string | null
          horas: number
          registrada_en?: string
        }
        Update: {
          id?: string
          persona_id?: string
          fecha?: string
          bloque?: Database["public"]["Enums"]["bloque_dia"]
          tipo?: string
          proyecto_id?: string | null
          fase_id?: string | null
          tarea_id?: string | null
          horas?: number
          registrada_en?: string
        }
        Relationships: [
          { foreignKeyName: "dedicacion_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "dedicacion_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "dedicacion_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "dedicacion_tarea_id_fkey"; columns: ["tarea_id"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] }
        ]
      }
      distribucion_estructura: {
        Row: {
          id: string
          periodo: string
          proyecto_id: string
          horas: number
          pct: number
          valor: number
          regla: string
          calculado_en: string
        }
        Insert: {
          id?: string
          periodo: string
          proyecto_id: string
          horas?: number
          pct?: number
          valor?: number
          regla?: string
          calculado_en?: string
        }
        Update: {
          id?: string
          periodo?: string
          proyecto_id?: string
          horas?: number
          pct?: number
          valor?: number
          regla?: string
          calculado_en?: string
        }
        Relationships: [
          { foreignKeyName: "distribucion_estructura_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      documento_obra: {
        Row: {
          id: string
          proyecto_id: string
          tipo: string
          titulo: string
          enlace: string
          fecha: string | null
          registrado_por: string
          registrado_en: string
          retirado_en: string | null
          retirado_por: string | null
        }
        Insert: {
          id?: string
          proyecto_id: string
          tipo?: string
          titulo: string
          enlace: string
          fecha?: string | null
          registrado_por: string
          registrado_en?: string
          retirado_en?: string | null
          retirado_por?: string | null
        }
        Update: {
          id?: string
          proyecto_id?: string
          tipo?: string
          titulo?: string
          enlace?: string
          fecha?: string | null
          registrado_por?: string
          registrado_en?: string
          retirado_en?: string | null
          retirado_por?: string | null
        }
        Relationships: [
          { foreignKeyName: "documento_obra_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "documento_obra_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "documento_obra_retirado_por_fkey"; columns: ["retirado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      ejecucion_item: {
        Row: {
          id: string
          item_id: string
          cantidad_proyectada: number
          valor_proyectado: number
          pct_avance: number
          valor_avance: number | null
          memoria_cantidades: string | null
          actualizado_por: string | null
          actualizado_en: string
        }
        Insert: {
          id?: string
          item_id: string
          cantidad_proyectada?: number
          valor_proyectado?: number
          pct_avance?: number
          valor_avance?: never
          memoria_cantidades?: string | null
          actualizado_por?: string | null
          actualizado_en?: string
        }
        Update: {
          id?: string
          item_id?: string
          cantidad_proyectada?: number
          valor_proyectado?: number
          pct_avance?: number
          valor_avance?: never
          memoria_cantidades?: string | null
          actualizado_por?: string | null
          actualizado_en?: string
        }
        Relationships: [
          { foreignKeyName: "ejecucion_item_actualizado_por_fkey"; columns: ["actualizado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "ejecucion_item_item_id_fkey"; columns: ["item_id"]; isOneToOne: true; referencedRelation: "item_presupuesto"; referencedColumns: ["id"] }
        ]
      }
      elemento_diseno: {
        Row: {
          id: string
          proyecto_id: string
          codigo: string
          nombre: string
          tipo: string
          especificacion: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          codigo: string
          nombre: string
          tipo?: string
          especificacion?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          codigo?: string
          nombre?: string
          tipo?: string
          especificacion?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "elemento_diseno_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      entregable: {
        Row: {
          id: string
          proyecto_id: string
          fase_id: string | null
          nombre: string
          version: number
          descripcion: string | null
          entregado_en: string
          entregado_a: string | null
          aprobado_cliente_en: string | null
          aprobado_por_texto: string | null
          registrado_por: string
          creado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          fase_id?: string | null
          nombre: string
          version?: number
          descripcion?: string | null
          entregado_en?: string
          entregado_a?: string | null
          aprobado_cliente_en?: string | null
          aprobado_por_texto?: string | null
          registrado_por: string
          creado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          fase_id?: string | null
          nombre?: string
          version?: number
          descripcion?: string | null
          entregado_en?: string
          entregado_a?: string | null
          aprobado_cliente_en?: string | null
          aprobado_por_texto?: string | null
          registrado_por?: string
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "entregable_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "entregable_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "entregable_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      entregable_archivo: {
        Row: {
          id: string
          entregable_id: string
          formato: string
          ruta: string
        }
        Insert: {
          id?: string
          entregable_id: string
          formato: string
          ruta: string
        }
        Update: {
          id?: string
          entregable_id?: string
          formato?: string
          ruta?: string
        }
        Relationships: [
          { foreignKeyName: "entregable_archivo_entregable_id_fkey"; columns: ["entregable_id"]; isOneToOne: false; referencedRelation: "entregable"; referencedColumns: ["id"] }
        ]
      }
      evento_auditoria: {
        Row: {
          id: number
          tabla: string
          fila_id: string
          operacion: string
          actor: string | null
          persona_id: string | null
          antes: Json | null
          despues: Json | null
          ocurrio_en: string
        }
        Insert: {
          id?: number
          tabla: string
          fila_id: string
          operacion: string
          actor?: string | null
          persona_id?: string | null
          antes?: Json | null
          despues?: Json | null
          ocurrio_en?: string
        }
        Update: {
          id?: number
          tabla?: string
          fila_id?: string
          operacion?: string
          actor?: string | null
          persona_id?: string | null
          antes?: Json | null
          despues?: Json | null
          ocurrio_en?: string
        }
        Relationships: []
      }
      evidencia: {
        Row: {
          id: string
          proyecto_id: string
          movimiento_id: string | null
          bitacora_id: string | null
          cambio_obra_id: string | null
          adicional_id: string | null
          reclamacion_id: string | null
          pendiente_id: string | null
          bucket: string
          ruta: string
          tipo: string
          lat: number | null
          lng: number | null
          tomada_en: string | null
          hash_sha256: string | null
          registrada_por: string
          subida_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          movimiento_id?: string | null
          bitacora_id?: string | null
          cambio_obra_id?: string | null
          adicional_id?: string | null
          reclamacion_id?: string | null
          pendiente_id?: string | null
          bucket?: string
          ruta: string
          tipo?: string
          lat?: number | null
          lng?: number | null
          tomada_en?: string | null
          hash_sha256?: string | null
          registrada_por: string
          subida_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          movimiento_id?: string | null
          bitacora_id?: string | null
          cambio_obra_id?: string | null
          adicional_id?: string | null
          reclamacion_id?: string | null
          pendiente_id?: string | null
          bucket?: string
          ruta?: string
          tipo?: string
          lat?: number | null
          lng?: number | null
          tomada_en?: string | null
          hash_sha256?: string | null
          registrada_por?: string
          subida_en?: string
        }
        Relationships: [
          { foreignKeyName: "evidencia_adicional_id_fkey"; columns: ["adicional_id"]; isOneToOne: false; referencedRelation: "adicional"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_bitacora_id_fkey"; columns: ["bitacora_id"]; isOneToOne: false; referencedRelation: "bitacora"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_cambio_obra_id_fkey"; columns: ["cambio_obra_id"]; isOneToOne: false; referencedRelation: "cambio_obra"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_movimiento_id_fkey"; columns: ["movimiento_id"]; isOneToOne: false; referencedRelation: "movimiento"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_pendiente_id_fkey"; columns: ["pendiente_id"]; isOneToOne: false; referencedRelation: "pendiente_obra"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_reclamacion_id_fkey"; columns: ["reclamacion_id"]; isOneToOne: false; referencedRelation: "reclamacion"; referencedColumns: ["id"] },
          { foreignKeyName: "evidencia_registrada_por_fkey"; columns: ["registrada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      experimento: {
        Row: {
          id: string
          nombre: string
          hipotesis: string | null
          metrica_exito: string | null
          umbral_exito: string | null
          inversion_prevista: number
          estado: Database["public"]["Enums"]["estado_experimento"]
          inicio: string | null
          fin: string | null
          resultado: string | null
          aprendizaje: string | null
          responsable_id: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          nombre: string
          hipotesis?: string | null
          metrica_exito?: string | null
          umbral_exito?: string | null
          inversion_prevista?: number
          estado?: Database["public"]["Enums"]["estado_experimento"]
          inicio?: string | null
          fin?: string | null
          resultado?: string | null
          aprendizaje?: string | null
          responsable_id?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          hipotesis?: string | null
          metrica_exito?: string | null
          umbral_exito?: string | null
          inversion_prevista?: number
          estado?: Database["public"]["Enums"]["estado_experimento"]
          inicio?: string | null
          fin?: string | null
          resultado?: string | null
          aprendizaje?: string | null
          responsable_id?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "experimento_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      extracto_linea: {
        Row: {
          id: string
          cuenta_id: string
          fecha: string
          valor: number
          descripcion: string | null
          referencia: string | null
          huella: string
          movimiento_id: string | null
          ingreso_id: string | null
          conciliada_en: string | null
          conciliada_por: string | null
          importada_en: string
        }
        Insert: {
          id?: string
          cuenta_id: string
          fecha: string
          valor: number
          descripcion?: string | null
          referencia?: string | null
          huella: string
          movimiento_id?: string | null
          ingreso_id?: string | null
          conciliada_en?: string | null
          conciliada_por?: string | null
          importada_en?: string
        }
        Update: {
          id?: string
          cuenta_id?: string
          fecha?: string
          valor?: number
          descripcion?: string | null
          referencia?: string | null
          huella?: string
          movimiento_id?: string | null
          ingreso_id?: string | null
          conciliada_en?: string | null
          conciliada_por?: string | null
          importada_en?: string
        }
        Relationships: [
          { foreignKeyName: "extracto_linea_conciliada_por_fkey"; columns: ["conciliada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "extracto_linea_cuenta_id_fkey"; columns: ["cuenta_id"]; isOneToOne: false; referencedRelation: "cuenta"; referencedColumns: ["id"] },
          { foreignKeyName: "extracto_linea_ingreso_id_fkey"; columns: ["ingreso_id"]; isOneToOne: false; referencedRelation: "ingreso"; referencedColumns: ["id"] },
          { foreignKeyName: "extracto_linea_movimiento_id_fkey"; columns: ["movimiento_id"]; isOneToOne: false; referencedRelation: "movimiento"; referencedColumns: ["id"] }
        ]
      }
      festivo: {
        Row: {
          fecha: string
          nombre: string
        }
        Insert: {
          fecha: string
          nombre: string
        }
        Update: {
          fecha?: string
          nombre?: string
        }
        Relationships: []
      }
      fondo_caja: {
        Row: {
          id: string
          responsable_id: string
          entregado_por: string
          valor: number
          fecha_entrega: string
          legalizado_en: string | null
          legalizado_por: string | null
          notas: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          responsable_id: string
          entregado_por: string
          valor: number
          fecha_entrega?: string
          legalizado_en?: string | null
          legalizado_por?: string | null
          notas?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          responsable_id?: string
          entregado_por?: string
          valor?: number
          fecha_entrega?: string
          legalizado_en?: string | null
          legalizado_por?: string | null
          notas?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "fondo_caja_entregado_por_fkey"; columns: ["entregado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "fondo_caja_legalizado_por_fkey"; columns: ["legalizado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "fondo_caja_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      ingreso: {
        Row: {
          id: string
          proyecto_id: string | null
          acta_id: string | null
          cuenta_id: string | null
          fecha: string
          valor: number
          linea: Database["public"]["Enums"]["linea_servicio"]
          es_anticipo: boolean
          tercero_id: string | null
          tercero_nombre: string | null
          concepto: string
          anula_a: string | null
          motivo_anulacion: string | null
          registrado_por: string
          registrado_en: string
          conciliado: boolean
          conciliado_en: string | null
        }
        Insert: {
          id?: string
          proyecto_id?: string | null
          acta_id?: string | null
          cuenta_id?: string | null
          fecha?: string
          valor: number
          linea: Database["public"]["Enums"]["linea_servicio"]
          es_anticipo?: boolean
          tercero_id?: string | null
          tercero_nombre?: string | null
          concepto: string
          anula_a?: string | null
          motivo_anulacion?: string | null
          registrado_por: string
          registrado_en?: string
          conciliado?: boolean
          conciliado_en?: string | null
        }
        Update: {
          id?: string
          proyecto_id?: string | null
          acta_id?: string | null
          cuenta_id?: string | null
          fecha?: string
          valor?: number
          linea?: Database["public"]["Enums"]["linea_servicio"]
          es_anticipo?: boolean
          tercero_id?: string | null
          tercero_nombre?: string | null
          concepto?: string
          anula_a?: string | null
          motivo_anulacion?: string | null
          registrado_por?: string
          registrado_en?: string
          conciliado?: boolean
          conciliado_en?: string | null
        }
        Relationships: [
          { foreignKeyName: "ingreso_acta_id_fkey"; columns: ["acta_id"]; isOneToOne: false; referencedRelation: "acta"; referencedColumns: ["id"] },
          { foreignKeyName: "ingreso_anula_a_fkey"; columns: ["anula_a"]; isOneToOne: true; referencedRelation: "ingreso"; referencedColumns: ["id"] },
          { foreignKeyName: "ingreso_cuenta_id_fkey"; columns: ["cuenta_id"]; isOneToOne: false; referencedRelation: "cuenta"; referencedColumns: ["id"] },
          { foreignKeyName: "ingreso_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "ingreso_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "ingreso_tercero_id_fkey"; columns: ["tercero_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      insumo: {
        Row: {
          id: string
          codigo: string | null
          descripcion: string
          unidad: string
          tipo: Database["public"]["Enums"]["tipo_insumo"]
          precio: number
          proveedor_id: string | null
          actualizado_en: string
          activo: boolean
        }
        Insert: {
          id?: string
          codigo?: string | null
          descripcion: string
          unidad: string
          tipo: Database["public"]["Enums"]["tipo_insumo"]
          precio?: number
          proveedor_id?: string | null
          actualizado_en?: string
          activo?: boolean
        }
        Update: {
          id?: string
          codigo?: string | null
          descripcion?: string
          unidad?: string
          tipo?: Database["public"]["Enums"]["tipo_insumo"]
          precio?: number
          proveedor_id?: string | null
          actualizado_en?: string
          activo?: boolean
        }
        Relationships: [
          { foreignKeyName: "insumo_proveedor_id_fkey"; columns: ["proveedor_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      inversion_pauta: {
        Row: {
          id: string
          campana_id: string
          fecha: string
          valor: number
          impresiones: number | null
          clics: number | null
          conversiones: number | null
          fuente: string
          importado_en: string
        }
        Insert: {
          id?: string
          campana_id: string
          fecha: string
          valor: number
          impresiones?: number | null
          clics?: number | null
          conversiones?: number | null
          fuente?: string
          importado_en?: string
        }
        Update: {
          id?: string
          campana_id?: string
          fecha?: string
          valor?: number
          impresiones?: number | null
          clics?: number | null
          conversiones?: number | null
          fuente?: string
          importado_en?: string
        }
        Relationships: [
          { foreignKeyName: "inversion_pauta_campana_id_fkey"; columns: ["campana_id"]; isOneToOne: false; referencedRelation: "campana"; referencedColumns: ["id"] }
        ]
      }
      item_presupuesto: {
        Row: {
          id: string
          capitulo_id: string
          codigo: string
          descripcion: string
          unidad: string | null
          cantidad: number
          valor_unitario: number
          valor_parcial: number | null
          apu_id: string | null
          elemento_id: string | null
        }
        Insert: {
          id?: string
          capitulo_id: string
          codigo: string
          descripcion: string
          unidad?: string | null
          cantidad?: number
          valor_unitario?: number
          valor_parcial?: never
          apu_id?: string | null
          elemento_id?: string | null
        }
        Update: {
          id?: string
          capitulo_id?: string
          codigo?: string
          descripcion?: string
          unidad?: string | null
          cantidad?: number
          valor_unitario?: number
          valor_parcial?: never
          apu_id?: string | null
          elemento_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "item_presupuesto_apu_id_fkey"; columns: ["apu_id"]; isOneToOne: false; referencedRelation: "apu"; referencedColumns: ["id"] },
          { foreignKeyName: "item_presupuesto_capitulo_id_fkey"; columns: ["capitulo_id"]; isOneToOne: false; referencedRelation: "capitulo"; referencedColumns: ["id"] },
          { foreignKeyName: "item_presupuesto_elemento_id_fkey"; columns: ["elemento_id"]; isOneToOne: false; referencedRelation: "elemento_diseno"; referencedColumns: ["id"] }
        ]
      }
      lead: {
        Row: {
          id: string
          creado_en: string
          canal: Database["public"]["Enums"]["canal_origen"]
          campana_id: string | null
          como_nos_encontro: Database["public"]["Enums"]["canal_origen"] | null
          gclid: string | null
          utm_source: string | null
          utm_medium: string | null
          utm_campaign: string | null
          landing: string | null
          nombre: string | null
          telefono: string | null
          telefono_normalizado: string | null
          correo: string | null
          ciudad: string | null
          mensaje_inicial: string | null
          estado: Database["public"]["Enums"]["estado_lead"]
          motivo_descarte: string | null
          puntaje: number | null
          asignado_a: string | null
          primer_contacto_en: string | null
          reactivado_en: string | null
          lead_previo_id: string | null
          referido_por: string | null
          id_pipedrive: string | null
        }
        Insert: {
          id?: string
          creado_en?: string
          canal: Database["public"]["Enums"]["canal_origen"]
          campana_id?: string | null
          como_nos_encontro?: Database["public"]["Enums"]["canal_origen"] | null
          gclid?: string | null
          utm_source?: string | null
          utm_medium?: string | null
          utm_campaign?: string | null
          landing?: string | null
          nombre?: string | null
          telefono?: string | null
          telefono_normalizado?: string | null
          correo?: string | null
          ciudad?: string | null
          mensaje_inicial?: string | null
          estado?: Database["public"]["Enums"]["estado_lead"]
          motivo_descarte?: string | null
          puntaje?: number | null
          asignado_a?: string | null
          primer_contacto_en?: string | null
          reactivado_en?: string | null
          lead_previo_id?: string | null
          referido_por?: string | null
          id_pipedrive?: string | null
        }
        Update: {
          id?: string
          creado_en?: string
          canal?: Database["public"]["Enums"]["canal_origen"]
          campana_id?: string | null
          como_nos_encontro?: Database["public"]["Enums"]["canal_origen"] | null
          gclid?: string | null
          utm_source?: string | null
          utm_medium?: string | null
          utm_campaign?: string | null
          landing?: string | null
          nombre?: string | null
          telefono?: string | null
          telefono_normalizado?: string | null
          correo?: string | null
          ciudad?: string | null
          mensaje_inicial?: string | null
          estado?: Database["public"]["Enums"]["estado_lead"]
          motivo_descarte?: string | null
          puntaje?: number | null
          asignado_a?: string | null
          primer_contacto_en?: string | null
          reactivado_en?: string | null
          lead_previo_id?: string | null
          referido_por?: string | null
          id_pipedrive?: string | null
        }
        Relationships: [
          { foreignKeyName: "lead_asignado_a_fkey"; columns: ["asignado_a"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "lead_campana_id_fkey"; columns: ["campana_id"]; isOneToOne: false; referencedRelation: "campana"; referencedColumns: ["id"] },
          { foreignKeyName: "lead_lead_previo_id_fkey"; columns: ["lead_previo_id"]; isOneToOne: false; referencedRelation: "lead"; referencedColumns: ["id"] }
        ]
      }
      lista_chequeo: {
        Row: {
          id: string
          ambito: Database["public"]["Enums"]["ambito_chequeo"]
          nombre: string
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          aseguradora_id: string | null
          version: number
          activa: boolean
          creada_en: string
          variante_id: string | null
          plantilla_id: string | null
        }
        Insert: {
          id?: string
          ambito: Database["public"]["Enums"]["ambito_chequeo"]
          nombre: string
          fase?: Database["public"]["Enums"]["fase_proyecto"] | null
          aseguradora_id?: string | null
          version?: number
          activa?: boolean
          creada_en?: string
          variante_id?: string | null
          plantilla_id?: string | null
        }
        Update: {
          id?: string
          ambito?: Database["public"]["Enums"]["ambito_chequeo"]
          nombre?: string
          fase?: Database["public"]["Enums"]["fase_proyecto"] | null
          aseguradora_id?: string | null
          version?: number
          activa?: boolean
          creada_en?: string
          variante_id?: string | null
          plantilla_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "lista_chequeo_aseguradora_id_fkey"; columns: ["aseguradora_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "lista_chequeo_plantilla_id_fkey"; columns: ["plantilla_id"]; isOneToOne: false; referencedRelation: "plantilla_proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "lista_chequeo_variante_id_fkey"; columns: ["variante_id"]; isOneToOne: false; referencedRelation: "variante_chequeo"; referencedColumns: ["id"] }
        ]
      }
      lista_chequeo_item: {
        Row: {
          id: string
          lista_id: string
          orden: number
          texto: string
          obligatorio: boolean
          requiere_evidencia: boolean
          tipo: string
          opciones: string[] | null
          activo: boolean
        }
        Insert: {
          id?: string
          lista_id: string
          orden?: number
          texto: string
          obligatorio?: boolean
          requiere_evidencia?: boolean
          tipo?: string
          opciones?: string[] | null
          activo?: boolean
        }
        Update: {
          id?: string
          lista_id?: string
          orden?: number
          texto?: string
          obligatorio?: boolean
          requiere_evidencia?: boolean
          tipo?: string
          opciones?: string[] | null
          activo?: boolean
        }
        Relationships: [
          { foreignKeyName: "lista_chequeo_item_lista_id_fkey"; columns: ["lista_id"]; isOneToOne: false; referencedRelation: "lista_chequeo"; referencedColumns: ["id"] }
        ]
      }
      mensaje: {
        Row: {
          id: string
          persona_id: string
          tipo: string
          clave: string
          texto: string
          proyecto_id: string | null
          tarea_id: string | null
          fase_id: string | null
          estado: string
          agrupado_en: string | null
          creado_en: string
          liberado_en: string | null
          enviado_en: string | null
          leido_en: string | null
        }
        Insert: {
          id?: string
          persona_id: string
          tipo: string
          clave: string
          texto: string
          proyecto_id?: string | null
          tarea_id?: string | null
          fase_id?: string | null
          estado?: string
          agrupado_en?: string | null
          creado_en?: string
          liberado_en?: string | null
          enviado_en?: string | null
          leido_en?: string | null
        }
        Update: {
          id?: string
          persona_id?: string
          tipo?: string
          clave?: string
          texto?: string
          proyecto_id?: string | null
          tarea_id?: string | null
          fase_id?: string | null
          estado?: string
          agrupado_en?: string | null
          creado_en?: string
          liberado_en?: string | null
          enviado_en?: string | null
          leido_en?: string | null
        }
        Relationships: [
          { foreignKeyName: "mensaje_agrupado_en_fkey"; columns: ["agrupado_en"]; isOneToOne: false; referencedRelation: "mensaje"; referencedColumns: ["id"] },
          { foreignKeyName: "mensaje_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "mensaje_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "mensaje_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "mensaje_tarea_id_fkey"; columns: ["tarea_id"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] },
          { foreignKeyName: "mensaje_tipo_fkey"; columns: ["tipo"]; isOneToOne: false; referencedRelation: "regla_mensaje"; referencedColumns: ["tipo"] }
        ]
      }
      movimiento: {
        Row: {
          id: string
          consecutivo: number
          proyecto_id: string
          centro_costo_id: string
          estado: Database["public"]["Enums"]["estado_dinero"]
          naturaleza: string
          fecha: string
          valor: number
          tercero_id: string | null
          tercero_nombre: string | null
          concepto: string
          medio: Database["public"]["Enums"]["medio_pago"]
          cuenta_id: string | null
          capitulo_id: string | null
          adicional_id: string | null
          acta_id: string | null
          fondo_id: string | null
          origen_id: string | null
          raiz_id: string | null
          fecha_prevista_pago: string | null
          aprobacion: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por: string | null
          aprobado_en: string | null
          anula_a: string | null
          motivo_anulacion: string | null
          registrado_por: string
          registrado_en: string
          sincronizado_en: string | null
          conciliado: boolean
          conciliado_en: string | null
          numero_factura: string | null
        }
        Insert: {
          id?: string
          consecutivo?: number
          proyecto_id: string
          centro_costo_id: string
          estado: Database["public"]["Enums"]["estado_dinero"]
          naturaleza?: string
          fecha?: string
          valor: number
          tercero_id?: string | null
          tercero_nombre?: string | null
          concepto: string
          medio?: Database["public"]["Enums"]["medio_pago"]
          cuenta_id?: string | null
          capitulo_id?: string | null
          adicional_id?: string | null
          acta_id?: string | null
          fondo_id?: string | null
          origen_id?: string | null
          raiz_id?: string | null
          fecha_prevista_pago?: string | null
          aprobacion?: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por?: string | null
          aprobado_en?: string | null
          anula_a?: string | null
          motivo_anulacion?: string | null
          registrado_por: string
          registrado_en?: string
          sincronizado_en?: string | null
          conciliado?: boolean
          conciliado_en?: string | null
          numero_factura?: string | null
        }
        Update: {
          id?: string
          consecutivo?: number
          proyecto_id?: string
          centro_costo_id?: string
          estado?: Database["public"]["Enums"]["estado_dinero"]
          naturaleza?: string
          fecha?: string
          valor?: number
          tercero_id?: string | null
          tercero_nombre?: string | null
          concepto?: string
          medio?: Database["public"]["Enums"]["medio_pago"]
          cuenta_id?: string | null
          capitulo_id?: string | null
          adicional_id?: string | null
          acta_id?: string | null
          fondo_id?: string | null
          origen_id?: string | null
          raiz_id?: string | null
          fecha_prevista_pago?: string | null
          aprobacion?: Database["public"]["Enums"]["estado_aprobacion"]
          aprobado_por?: string | null
          aprobado_en?: string | null
          anula_a?: string | null
          motivo_anulacion?: string | null
          registrado_por?: string
          registrado_en?: string
          sincronizado_en?: string | null
          conciliado?: boolean
          conciliado_en?: string | null
          numero_factura?: string | null
        }
        Relationships: [
          { foreignKeyName: "movimiento_acta_id_fkey"; columns: ["acta_id"]; isOneToOne: false; referencedRelation: "acta"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_adicional_id_fkey"; columns: ["adicional_id"]; isOneToOne: false; referencedRelation: "adicional"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_anula_a_fkey"; columns: ["anula_a"]; isOneToOne: true; referencedRelation: "movimiento"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_aprobado_por_fkey"; columns: ["aprobado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_capitulo_id_fkey"; columns: ["capitulo_id"]; isOneToOne: false; referencedRelation: "capitulo"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_centro_costo_id_fkey"; columns: ["centro_costo_id"]; isOneToOne: false; referencedRelation: "centro_costo"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_cuenta_id_fkey"; columns: ["cuenta_id"]; isOneToOne: false; referencedRelation: "cuenta"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_fondo_id_fkey"; columns: ["fondo_id"]; isOneToOne: false; referencedRelation: "fondo_caja"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_origen_id_fkey"; columns: ["origen_id"]; isOneToOne: false; referencedRelation: "movimiento"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "movimiento_tercero_id_fkey"; columns: ["tercero_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      objetivo: {
        Row: {
          id: string
          ambito: Database["public"]["Enums"]["ambito_objetivo"]
          proyecto_id: string | null
          persona_id: string | null
          titulo: string
          fecha_limite: string
          responsable_id: string
          estado: Database["public"]["Enums"]["estado_objetivo"]
          cerrado_en: string | null
          cerrado_por: string | null
          creado_en: string
          creado_por: string
        }
        Insert: {
          id?: string
          ambito: Database["public"]["Enums"]["ambito_objetivo"]
          proyecto_id?: string | null
          persona_id?: string | null
          titulo: string
          fecha_limite: string
          responsable_id: string
          estado?: Database["public"]["Enums"]["estado_objetivo"]
          cerrado_en?: string | null
          cerrado_por?: string | null
          creado_en?: string
          creado_por: string
        }
        Update: {
          id?: string
          ambito?: Database["public"]["Enums"]["ambito_objetivo"]
          proyecto_id?: string | null
          persona_id?: string | null
          titulo?: string
          fecha_limite?: string
          responsable_id?: string
          estado?: Database["public"]["Enums"]["estado_objetivo"]
          cerrado_en?: string | null
          cerrado_por?: string | null
          creado_en?: string
          creado_por?: string
        }
        Relationships: [
          { foreignKeyName: "objetivo_cerrado_por_fkey"; columns: ["cerrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "objetivo_creado_por_fkey"; columns: ["creado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "objetivo_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "objetivo_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "objetivo_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      oportunidad: {
        Row: {
          id: string
          lead_id: string | null
          cliente_id: string | null
          nombre: string
          unidad: Database["public"]["Enums"]["unidad_negocio"] | null
          canal: Database["public"]["Enums"]["canal_origen"]
          etapa: Database["public"]["Enums"]["etapa_oportunidad"]
          valor_estimado: number | null
          area_m2: number | null
          ciudad: string | null
          responsable_id: string | null
          motivo_perdida: Database["public"]["Enums"]["motivo_perdida"] | null
          detalle_perdida: string | null
          desenlace_en: string | null
          conversion_enviada_en: string | null
          id_pipedrive: string | null
          creada_en: string
          actualizada_en: string
          siguiente_paso: string | null
          siguiente_paso_en: string | null
          siguiente_paso_por: string | null
          etapa_desde: string
          origen_oportunidad_id: string | null
          origen_proyecto_id: string | null
        }
        Insert: {
          id?: string
          lead_id?: string | null
          cliente_id?: string | null
          nombre: string
          unidad?: Database["public"]["Enums"]["unidad_negocio"] | null
          canal: Database["public"]["Enums"]["canal_origen"]
          etapa?: Database["public"]["Enums"]["etapa_oportunidad"]
          valor_estimado?: number | null
          area_m2?: number | null
          ciudad?: string | null
          responsable_id?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          detalle_perdida?: string | null
          desenlace_en?: string | null
          conversion_enviada_en?: string | null
          id_pipedrive?: string | null
          creada_en?: string
          actualizada_en?: string
          siguiente_paso?: string | null
          siguiente_paso_en?: string | null
          siguiente_paso_por?: string | null
          etapa_desde?: string
          origen_oportunidad_id?: string | null
          origen_proyecto_id?: string | null
        }
        Update: {
          id?: string
          lead_id?: string | null
          cliente_id?: string | null
          nombre?: string
          unidad?: Database["public"]["Enums"]["unidad_negocio"] | null
          canal?: Database["public"]["Enums"]["canal_origen"]
          etapa?: Database["public"]["Enums"]["etapa_oportunidad"]
          valor_estimado?: number | null
          area_m2?: number | null
          ciudad?: string | null
          responsable_id?: string | null
          motivo_perdida?: Database["public"]["Enums"]["motivo_perdida"] | null
          detalle_perdida?: string | null
          desenlace_en?: string | null
          conversion_enviada_en?: string | null
          id_pipedrive?: string | null
          creada_en?: string
          actualizada_en?: string
          siguiente_paso?: string | null
          siguiente_paso_en?: string | null
          siguiente_paso_por?: string | null
          etapa_desde?: string
          origen_oportunidad_id?: string | null
          origen_proyecto_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "oportunidad_cliente_id_fkey"; columns: ["cliente_id"]; isOneToOne: false; referencedRelation: "cliente"; referencedColumns: ["id"] },
          { foreignKeyName: "oportunidad_lead_id_fkey"; columns: ["lead_id"]; isOneToOne: false; referencedRelation: "lead"; referencedColumns: ["id"] },
          { foreignKeyName: "oportunidad_origen_oportunidad_id_fkey"; columns: ["origen_oportunidad_id"]; isOneToOne: false; referencedRelation: "oportunidad"; referencedColumns: ["id"] },
          { foreignKeyName: "oportunidad_origen_proyecto_id_fkey"; columns: ["origen_proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "oportunidad_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "oportunidad_siguiente_paso_por_fkey"; columns: ["siguiente_paso_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      parametro: {
        Row: {
          id: boolean
          umbral_aprobacion: number
          margen_meta_obra: number
          margen_meta_diseno: number
          imprevistos_minimo: number
          caja_minima: number
          vigencia_cotizacion_dias: number
          intentos_contacto_max: number
          minutos_primera_respuesta: number
          dias_sin_desenlace: number
          horas_por_bloque: number
          dias_edicion_dedicacion: number
          dias_legalizar_caja: number
          dias_aviso_poliza: number
          dias_pago_estimado: number
          actualizado_en: string
          dias_habiles_revision: number
          semanas_indicador: number
          minimo_revisadas_indicador: number
          peso_alta: number
          peso_bloqueante: number
          mensajes_max_dia: number
          mensajes_desde: string
          mensajes_hasta: string
          hora_registro_dia: string
          hora_tu_semana: string
          responsable_obra_id: string | null
          dias_oferta_obra: number
          dias_entre_intentos: number
          meta_ventas_diseno_mes: number | null
        }
        Insert: {
          id?: boolean
          umbral_aprobacion?: number
          margen_meta_obra?: number
          margen_meta_diseno?: number
          imprevistos_minimo?: number
          caja_minima?: number
          vigencia_cotizacion_dias?: number
          intentos_contacto_max?: number
          minutos_primera_respuesta?: number
          dias_sin_desenlace?: number
          horas_por_bloque?: number
          dias_edicion_dedicacion?: number
          dias_legalizar_caja?: number
          dias_aviso_poliza?: number
          dias_pago_estimado?: number
          actualizado_en?: string
          dias_habiles_revision?: number
          semanas_indicador?: number
          minimo_revisadas_indicador?: number
          peso_alta?: number
          peso_bloqueante?: number
          mensajes_max_dia?: number
          mensajes_desde?: string
          mensajes_hasta?: string
          hora_registro_dia?: string
          hora_tu_semana?: string
          responsable_obra_id?: string | null
          dias_oferta_obra?: number
          dias_entre_intentos?: number
          meta_ventas_diseno_mes?: number | null
        }
        Update: {
          id?: boolean
          umbral_aprobacion?: number
          margen_meta_obra?: number
          margen_meta_diseno?: number
          imprevistos_minimo?: number
          caja_minima?: number
          vigencia_cotizacion_dias?: number
          intentos_contacto_max?: number
          minutos_primera_respuesta?: number
          dias_sin_desenlace?: number
          horas_por_bloque?: number
          dias_edicion_dedicacion?: number
          dias_legalizar_caja?: number
          dias_aviso_poliza?: number
          dias_pago_estimado?: number
          actualizado_en?: string
          dias_habiles_revision?: number
          semanas_indicador?: number
          minimo_revisadas_indicador?: number
          peso_alta?: number
          peso_bloqueante?: number
          mensajes_max_dia?: number
          mensajes_desde?: string
          mensajes_hasta?: string
          hora_registro_dia?: string
          hora_tu_semana?: string
          responsable_obra_id?: string | null
          dias_oferta_obra?: number
          dias_entre_intentos?: number
          meta_ventas_diseno_mes?: number | null
        }
        Relationships: [
          { foreignKeyName: "parametro_responsable_obra_id_fkey"; columns: ["responsable_obra_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      partida_abierta: {
        Row: {
          id: string
          cuenta_id: string
          extracto_linea_id: string | null
          fecha: string
          valor: number
          descripcion: string
          responsable_id: string
          abierta_en: string
          resuelta_en: string | null
          resuelta_por: string | null
          resolucion: string | null
        }
        Insert: {
          id?: string
          cuenta_id: string
          extracto_linea_id?: string | null
          fecha: string
          valor: number
          descripcion: string
          responsable_id: string
          abierta_en?: string
          resuelta_en?: string | null
          resuelta_por?: string | null
          resolucion?: string | null
        }
        Update: {
          id?: string
          cuenta_id?: string
          extracto_linea_id?: string | null
          fecha?: string
          valor?: number
          descripcion?: string
          responsable_id?: string
          abierta_en?: string
          resuelta_en?: string | null
          resuelta_por?: string | null
          resolucion?: string | null
        }
        Relationships: [
          { foreignKeyName: "partida_abierta_cuenta_id_fkey"; columns: ["cuenta_id"]; isOneToOne: false; referencedRelation: "cuenta"; referencedColumns: ["id"] },
          { foreignKeyName: "partida_abierta_extracto_linea_id_fkey"; columns: ["extracto_linea_id"]; isOneToOne: false; referencedRelation: "extracto_linea"; referencedColumns: ["id"] },
          { foreignKeyName: "partida_abierta_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "partida_abierta_resuelta_por_fkey"; columns: ["resuelta_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      pendiente_obra: {
        Row: {
          id: string
          proyecto_id: string
          fase_id: string | null
          objetivo_id: string | null
          elemento_id: string | null
          tipo: Database["public"]["Enums"]["tipo_pendiente"]
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"]
          titulo: string
          ubicacion: string | null
          descripcion: string | null
          responsable_id: string
          ejecutor_id: string | null
          bloqueado_por: string | null
          movimiento_id: string | null
          estado: Database["public"]["Enums"]["estado_pendiente"]
          fecha_compromiso: string | null
          verificado_en: string | null
          verificado_por: string | null
          descartado_porque: string | null
          creado_en: string
          creado_por: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          fase_id?: string | null
          objetivo_id?: string | null
          elemento_id?: string | null
          tipo?: Database["public"]["Enums"]["tipo_pendiente"]
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          titulo: string
          ubicacion?: string | null
          descripcion?: string | null
          responsable_id: string
          ejecutor_id?: string | null
          bloqueado_por?: string | null
          movimiento_id?: string | null
          estado?: Database["public"]["Enums"]["estado_pendiente"]
          fecha_compromiso?: string | null
          verificado_en?: string | null
          verificado_por?: string | null
          descartado_porque?: string | null
          creado_en?: string
          creado_por: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          fase_id?: string | null
          objetivo_id?: string | null
          elemento_id?: string | null
          tipo?: Database["public"]["Enums"]["tipo_pendiente"]
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          titulo?: string
          ubicacion?: string | null
          descripcion?: string | null
          responsable_id?: string
          ejecutor_id?: string | null
          bloqueado_por?: string | null
          movimiento_id?: string | null
          estado?: Database["public"]["Enums"]["estado_pendiente"]
          fecha_compromiso?: string | null
          verificado_en?: string | null
          verificado_por?: string | null
          descartado_porque?: string | null
          creado_en?: string
          creado_por?: string
        }
        Relationships: [
          { foreignKeyName: "pendiente_obra_bloqueado_por_fkey"; columns: ["bloqueado_por"]; isOneToOne: false; referencedRelation: "pendiente_obra"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_creado_por_fkey"; columns: ["creado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_ejecutor_id_fkey"; columns: ["ejecutor_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_elemento_id_fkey"; columns: ["elemento_id"]; isOneToOne: false; referencedRelation: "elemento_diseno"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_movimiento_id_fkey"; columns: ["movimiento_id"]; isOneToOne: false; referencedRelation: "movimiento"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_objetivo_id_fkey"; columns: ["objetivo_id"]; isOneToOne: false; referencedRelation: "objetivo"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "pendiente_obra_verificado_por_fkey"; columns: ["verificado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      persona: {
        Row: {
          id: string
          nombre: string
          rol: Database["public"]["Enums"]["rol_persona"]
          documento: string | null
          nit: string | null
          correo: string | null
          telefono: string | null
          es_interno: boolean
          auth_user_id: string | null
          horas_semana: number
          activo: boolean
          notas: string | null
          creado_en: string
          profesion_id: string | null
          ve_reservado: boolean
        }
        Insert: {
          id?: string
          nombre: string
          rol: Database["public"]["Enums"]["rol_persona"]
          documento?: string | null
          nit?: string | null
          correo?: string | null
          telefono?: string | null
          es_interno?: boolean
          auth_user_id?: string | null
          horas_semana?: number
          activo?: boolean
          notas?: string | null
          creado_en?: string
          profesion_id?: string | null
          ve_reservado?: boolean
        }
        Update: {
          id?: string
          nombre?: string
          rol?: Database["public"]["Enums"]["rol_persona"]
          documento?: string | null
          nit?: string | null
          correo?: string | null
          telefono?: string | null
          es_interno?: boolean
          auth_user_id?: string | null
          horas_semana?: number
          activo?: boolean
          notas?: string | null
          creado_en?: string
          profesion_id?: string | null
          ve_reservado?: boolean
        }
        Relationships: [
          { foreignKeyName: "persona_auth_user_id_fkey"; columns: ["auth_user_id"]; isOneToOne: true; referencedRelation: "users"; referencedColumns: ["id"] },
          { foreignKeyName: "persona_profesion_id_fkey"; columns: ["profesion_id"]; isOneToOne: false; referencedRelation: "profesion"; referencedColumns: ["id"] }
        ]
      }
      plantilla_fase: {
        Row: {
          id: string
          plantilla_id: string
          fase: Database["public"]["Enums"]["fase_proyecto"]
          orden: number
          entrega_cliente: string | null
          opcional: boolean
          exige_chequeo: boolean
          exige_aprobacion_cliente: boolean
          exige_dedicacion: boolean
          dias_habiles_plazo: number | null
          responsable_papel: Database["public"]["Enums"]["papel_proyecto"]
        }
        Insert: {
          id?: string
          plantilla_id: string
          fase: Database["public"]["Enums"]["fase_proyecto"]
          orden: number
          entrega_cliente?: string | null
          opcional?: boolean
          exige_chequeo?: boolean
          exige_aprobacion_cliente?: boolean
          exige_dedicacion?: boolean
          dias_habiles_plazo?: number | null
          responsable_papel?: Database["public"]["Enums"]["papel_proyecto"]
        }
        Update: {
          id?: string
          plantilla_id?: string
          fase?: Database["public"]["Enums"]["fase_proyecto"]
          orden?: number
          entrega_cliente?: string | null
          opcional?: boolean
          exige_chequeo?: boolean
          exige_aprobacion_cliente?: boolean
          exige_dedicacion?: boolean
          dias_habiles_plazo?: number | null
          responsable_papel?: Database["public"]["Enums"]["papel_proyecto"]
        }
        Relationships: [
          { foreignKeyName: "plantilla_fase_plantilla_id_fkey"; columns: ["plantilla_id"]; isOneToOne: false; referencedRelation: "plantilla_proyecto"; referencedColumns: ["id"] }
        ]
      }
      plantilla_proyecto: {
        Row: {
          id: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          descripcion: string | null
          activa: boolean
          creada_en: string
        }
        Insert: {
          id?: string
          nombre: string
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          descripcion?: string | null
          activa?: boolean
          creada_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          tipo?: Database["public"]["Enums"]["tipo_proyecto"]
          descripcion?: string | null
          activa?: boolean
          creada_en?: string
        }
        Relationships: []
      }
      plantilla_tarea: {
        Row: {
          id: string
          plantilla_fase_id: string
          orden: number
          titulo: string
          proposito: string
          por_espacio: boolean
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"]
          dias_plazo: number | null
          depende_de: string | null
          activa: boolean
          dias_estimados: number | null
        }
        Insert: {
          id?: string
          plantilla_fase_id: string
          orden?: number
          titulo: string
          proposito: string
          por_espacio?: boolean
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          dias_plazo?: number | null
          depende_de?: string | null
          activa?: boolean
          dias_estimados?: number | null
        }
        Update: {
          id?: string
          plantilla_fase_id?: string
          orden?: number
          titulo?: string
          proposito?: string
          por_espacio?: boolean
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          dias_plazo?: number | null
          depende_de?: string | null
          activa?: boolean
          dias_estimados?: number | null
        }
        Relationships: [
          { foreignKeyName: "plantilla_tarea_depende_de_fkey"; columns: ["depende_de"]; isOneToOne: false; referencedRelation: "plantilla_tarea"; referencedColumns: ["id"] },
          { foreignKeyName: "plantilla_tarea_plantilla_fase_id_fkey"; columns: ["plantilla_fase_id"]; isOneToOne: false; referencedRelation: "plantilla_fase"; referencedColumns: ["id"] }
        ]
      }
      presupuesto: {
        Row: {
          id: string
          proyecto_id: string
          version: number
          vigente: boolean
          estado: Database["public"]["Enums"]["estado_presupuesto"]
          elaborado_por: string | null
          validado_por: string | null
          validado_en: string | null
          aprobado_por: string | null
          aprobado_en: string | null
          justificacion_imprevistos: string | null
          margen_autorizado_por: string | null
          margen_autorizado_en: string | null
          notas: string | null
          creado_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          version?: number
          vigente?: boolean
          estado?: Database["public"]["Enums"]["estado_presupuesto"]
          elaborado_por?: string | null
          validado_por?: string | null
          validado_en?: string | null
          aprobado_por?: string | null
          aprobado_en?: string | null
          justificacion_imprevistos?: string | null
          margen_autorizado_por?: string | null
          margen_autorizado_en?: string | null
          notas?: string | null
          creado_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          version?: number
          vigente?: boolean
          estado?: Database["public"]["Enums"]["estado_presupuesto"]
          elaborado_por?: string | null
          validado_por?: string | null
          validado_en?: string | null
          aprobado_por?: string | null
          aprobado_en?: string | null
          justificacion_imprevistos?: string | null
          margen_autorizado_por?: string | null
          margen_autorizado_en?: string | null
          notas?: string | null
          creado_en?: string
        }
        Relationships: [
          { foreignKeyName: "presupuesto_aprobado_por_fkey"; columns: ["aprobado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "presupuesto_elaborado_por_fkey"; columns: ["elaborado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "presupuesto_margen_autorizado_por_fkey"; columns: ["margen_autorizado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "presupuesto_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "presupuesto_validado_por_fkey"; columns: ["validado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      profesion: {
        Row: {
          id: string
          nombre: string
          activa: boolean
        }
        Insert: {
          id?: string
          nombre: string
          activa?: boolean
        }
        Update: {
          id?: string
          nombre?: string
          activa?: boolean
        }
        Relationships: []
      }
      proyecto: {
        Row: {
          id: string
          codigo: string
          nombre: string
          unidad: Database["public"]["Enums"]["unidad_negocio"]
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          estado: Database["public"]["Enums"]["estado_proyecto"]
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          cliente_id: string | null
          oportunidad_id: string | null
          responsable_id: string | null
          residente_id: string | null
          canal: Database["public"]["Enums"]["canal_origen"] | null
          valor_contrato: number | null
          pct_administracion: number | null
          pct_utilidad: number | null
          pct_imprevistos: number | null
          area_m2: number | null
          ciudad: string | null
          fecha_inicio: string | null
          fecha_fin_prevista: string | null
          es_reclamacion: boolean
          creado_en: string
          plantilla_id: string | null
          variante_chequeo_id: string | null
          carpeta_drive: string | null
          reservado: boolean
        }
        Insert: {
          id?: string
          codigo: string
          nombre: string
          unidad: Database["public"]["Enums"]["unidad_negocio"]
          tipo: Database["public"]["Enums"]["tipo_proyecto"]
          estado?: Database["public"]["Enums"]["estado_proyecto"]
          fase?: Database["public"]["Enums"]["fase_proyecto"] | null
          cliente_id?: string | null
          oportunidad_id?: string | null
          responsable_id?: string | null
          residente_id?: string | null
          canal?: Database["public"]["Enums"]["canal_origen"] | null
          valor_contrato?: number | null
          pct_administracion?: number | null
          pct_utilidad?: number | null
          pct_imprevistos?: number | null
          area_m2?: number | null
          ciudad?: string | null
          fecha_inicio?: string | null
          fecha_fin_prevista?: string | null
          es_reclamacion?: boolean
          creado_en?: string
          plantilla_id?: string | null
          variante_chequeo_id?: string | null
          carpeta_drive?: string | null
          reservado?: boolean
        }
        Update: {
          id?: string
          codigo?: string
          nombre?: string
          unidad?: Database["public"]["Enums"]["unidad_negocio"]
          tipo?: Database["public"]["Enums"]["tipo_proyecto"]
          estado?: Database["public"]["Enums"]["estado_proyecto"]
          fase?: Database["public"]["Enums"]["fase_proyecto"] | null
          cliente_id?: string | null
          oportunidad_id?: string | null
          responsable_id?: string | null
          residente_id?: string | null
          canal?: Database["public"]["Enums"]["canal_origen"] | null
          valor_contrato?: number | null
          pct_administracion?: number | null
          pct_utilidad?: number | null
          pct_imprevistos?: number | null
          area_m2?: number | null
          ciudad?: string | null
          fecha_inicio?: string | null
          fecha_fin_prevista?: string | null
          es_reclamacion?: boolean
          creado_en?: string
          plantilla_id?: string | null
          variante_chequeo_id?: string | null
          carpeta_drive?: string | null
          reservado?: boolean
        }
        Relationships: [
          { foreignKeyName: "proyecto_cliente_id_fkey"; columns: ["cliente_id"]; isOneToOne: false; referencedRelation: "cliente"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_oportunidad_id_fkey"; columns: ["oportunidad_id"]; isOneToOne: false; referencedRelation: "oportunidad"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_plantilla_id_fkey"; columns: ["plantilla_id"]; isOneToOne: false; referencedRelation: "plantilla_proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_residente_id_fkey"; columns: ["residente_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_variante_chequeo_id_fkey"; columns: ["variante_chequeo_id"]; isOneToOne: false; referencedRelation: "variante_chequeo"; referencedColumns: ["id"] }
        ]
      }
      proyecto_fase: {
        Row: {
          id: string
          proyecto_id: string
          fase: Database["public"]["Enums"]["fase_proyecto"]
          orden: number
          estado: Database["public"]["Enums"]["estado_fase"]
          horas_cotizadas: number
          fecha_inicio: string | null
          fecha_compromiso: string | null
          aprobada_cliente_en: string | null
          aprobada_cliente_texto: string | null
          cerrada_en: string | null
          cerrada_por: string | null
          creada_en: string
          exige_chequeo: boolean
          exige_aprobacion_cliente: boolean
          exige_dedicacion: boolean
          entrega_cliente: string | null
          dias_habiles_plazo: number | null
          responsable_id: string | null
        }
        Insert: {
          id?: string
          proyecto_id: string
          fase: Database["public"]["Enums"]["fase_proyecto"]
          orden: number
          estado?: Database["public"]["Enums"]["estado_fase"]
          horas_cotizadas?: number
          fecha_inicio?: string | null
          fecha_compromiso?: string | null
          aprobada_cliente_en?: string | null
          aprobada_cliente_texto?: string | null
          cerrada_en?: string | null
          cerrada_por?: string | null
          creada_en?: string
          exige_chequeo?: boolean
          exige_aprobacion_cliente?: boolean
          exige_dedicacion?: boolean
          entrega_cliente?: string | null
          dias_habiles_plazo?: number | null
          responsable_id?: string | null
        }
        Update: {
          id?: string
          proyecto_id?: string
          fase?: Database["public"]["Enums"]["fase_proyecto"]
          orden?: number
          estado?: Database["public"]["Enums"]["estado_fase"]
          horas_cotizadas?: number
          fecha_inicio?: string | null
          fecha_compromiso?: string | null
          aprobada_cliente_en?: string | null
          aprobada_cliente_texto?: string | null
          cerrada_en?: string | null
          cerrada_por?: string | null
          creada_en?: string
          exige_chequeo?: boolean
          exige_aprobacion_cliente?: boolean
          exige_dedicacion?: boolean
          entrega_cliente?: string | null
          dias_habiles_plazo?: number | null
          responsable_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "proyecto_fase_cerrada_por_fkey"; columns: ["cerrada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_fase_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "proyecto_fase_responsable_id_fkey"; columns: ["responsable_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      radicacion_licencia: {
        Row: {
          id: string
          proyecto_id: string
          curaduria: string
          municipio: string
          estado: Database["public"]["Enums"]["estado_radicacion"]
          numero_radicado: string | null
          radicada_en: string | null
          observaciones: string | null
          resuelta_en: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          curaduria: string
          municipio: string
          estado?: Database["public"]["Enums"]["estado_radicacion"]
          numero_radicado?: string | null
          radicada_en?: string | null
          observaciones?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          curaduria?: string
          municipio?: string
          estado?: Database["public"]["Enums"]["estado_radicacion"]
          numero_radicado?: string | null
          radicada_en?: string | null
          observaciones?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "radicacion_licencia_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      reclamacion: {
        Row: {
          id: string
          proyecto_id: string
          aseguradora_id: string | null
          oficina_abogados_id: string | null
          numero_poliza: string | null
          numero_siniestro: string | null
          fecha_siniestro: string | null
          fecha_limite: string | null
          valor_reclamado: number | null
          valor_aprobado: number | null
          estado: Database["public"]["Enums"]["estado_reclamacion"]
          conciliada_en: string | null
          conciliada_por_texto: string | null
          aval_estructural_por: string | null
          aval_estructural_en: string | null
          radicada_en: string | null
          notas: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          proyecto_id: string
          aseguradora_id?: string | null
          oficina_abogados_id?: string | null
          numero_poliza?: string | null
          numero_siniestro?: string | null
          fecha_siniestro?: string | null
          fecha_limite?: string | null
          valor_reclamado?: number | null
          valor_aprobado?: number | null
          estado?: Database["public"]["Enums"]["estado_reclamacion"]
          conciliada_en?: string | null
          conciliada_por_texto?: string | null
          aval_estructural_por?: string | null
          aval_estructural_en?: string | null
          radicada_en?: string | null
          notas?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          proyecto_id?: string
          aseguradora_id?: string | null
          oficina_abogados_id?: string | null
          numero_poliza?: string | null
          numero_siniestro?: string | null
          fecha_siniestro?: string | null
          fecha_limite?: string | null
          valor_reclamado?: number | null
          valor_aprobado?: number | null
          estado?: Database["public"]["Enums"]["estado_reclamacion"]
          conciliada_en?: string | null
          conciliada_por_texto?: string | null
          aval_estructural_por?: string | null
          aval_estructural_en?: string | null
          radicada_en?: string | null
          notas?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "reclamacion_aseguradora_id_fkey"; columns: ["aseguradora_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "reclamacion_aval_estructural_por_fkey"; columns: ["aval_estructural_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "reclamacion_oficina_abogados_id_fkey"; columns: ["oficina_abogados_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "reclamacion_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: true; referencedRelation: "proyecto"; referencedColumns: ["id"] }
        ]
      }
      reclamacion_evento: {
        Row: {
          id: number
          reclamacion_id: string
          estado_anterior: Database["public"]["Enums"]["estado_reclamacion"] | null
          estado_nuevo: Database["public"]["Enums"]["estado_reclamacion"]
          persona_id: string | null
          ocurrio_en: string
        }
        Insert: {
          id?: number
          reclamacion_id: string
          estado_anterior?: Database["public"]["Enums"]["estado_reclamacion"] | null
          estado_nuevo: Database["public"]["Enums"]["estado_reclamacion"]
          persona_id?: string | null
          ocurrio_en?: string
        }
        Update: {
          id?: number
          reclamacion_id?: string
          estado_anterior?: Database["public"]["Enums"]["estado_reclamacion"] | null
          estado_nuevo?: Database["public"]["Enums"]["estado_reclamacion"]
          persona_id?: string | null
          ocurrio_en?: string
        }
        Relationships: [
          { foreignKeyName: "reclamacion_evento_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "reclamacion_evento_reclamacion_id_fkey"; columns: ["reclamacion_id"]; isOneToOne: false; referencedRelation: "reclamacion"; referencedColumns: ["id"] }
        ]
      }
      regla_alerta: {
        Row: {
          tipo: string
          descripcion: string
          severidad: Database["public"]["Enums"]["severidad"]
          roles: Database["public"]["Enums"]["rol_persona"][]
          incluir_residente: boolean
          incluir_responsable: boolean
          canales: Database["public"]["Enums"]["canal_aviso"][]
          activa: boolean
        }
        Insert: {
          tipo: string
          descripcion: string
          severidad?: Database["public"]["Enums"]["severidad"]
          roles?: Database["public"]["Enums"]["rol_persona"][]
          incluir_residente?: boolean
          incluir_responsable?: boolean
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          activa?: boolean
        }
        Update: {
          tipo?: string
          descripcion?: string
          severidad?: Database["public"]["Enums"]["severidad"]
          roles?: Database["public"]["Enums"]["rol_persona"][]
          incluir_residente?: boolean
          incluir_responsable?: boolean
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          activa?: boolean
        }
        Relationships: []
      }
      regla_mensaje: {
        Row: {
          tipo: string
          descripcion: string
          prioridad: number
          cuenta_en_limite: boolean
          canales: Database["public"]["Enums"]["canal_aviso"][]
          activa: boolean
        }
        Insert: {
          tipo: string
          descripcion: string
          prioridad?: number
          cuenta_en_limite?: boolean
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          activa?: boolean
        }
        Update: {
          tipo?: string
          descripcion?: string
          prioridad?: number
          cuenta_en_limite?: boolean
          canales?: Database["public"]["Enums"]["canal_aviso"][]
          activa?: boolean
        }
        Relationships: []
      }
      revision_diseno: {
        Row: {
          id: string
          tarea_id: string
          revisor_id: string
          resultado: string
          observaciones: string | null
          revisada_en: string
        }
        Insert: {
          id?: string
          tarea_id: string
          revisor_id: string
          resultado: string
          observaciones?: string | null
          revisada_en?: string
        }
        Update: {
          id?: string
          tarea_id?: string
          revisor_id?: string
          resultado?: string
          observaciones?: string | null
          revisada_en?: string
        }
        Relationships: [
          { foreignKeyName: "revision_diseno_revisor_id_fkey"; columns: ["revisor_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "revision_diseno_tarea_id_fkey"; columns: ["tarea_id"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] }
        ]
      }
      saldo_cuenta: {
        Row: {
          id: string
          cuenta_id: string
          fecha: string
          saldo: number
          fuente: string
          registrado_por: string | null
          registrado_en: string
        }
        Insert: {
          id?: string
          cuenta_id: string
          fecha: string
          saldo: number
          fuente?: string
          registrado_por?: string | null
          registrado_en?: string
        }
        Update: {
          id?: string
          cuenta_id?: string
          fecha?: string
          saldo?: number
          fuente?: string
          registrado_por?: string | null
          registrado_en?: string
        }
        Relationships: [
          { foreignKeyName: "saldo_cuenta_cuenta_id_fkey"; columns: ["cuenta_id"]; isOneToOne: false; referencedRelation: "cuenta"; referencedColumns: ["id"] },
          { foreignKeyName: "saldo_cuenta_registrado_por_fkey"; columns: ["registrado_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      solicitud_correccion: {
        Row: {
          id: string
          persona_id: string
          indicador: string
          tarea_id: string | null
          fase_id: string | null
          motivo: string
          estado: string
          excluir: boolean
          respuesta: string | null
          resuelta_por: string | null
          resuelta_en: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          persona_id: string
          indicador: string
          tarea_id?: string | null
          fase_id?: string | null
          motivo: string
          estado?: string
          excluir?: boolean
          respuesta?: string | null
          resuelta_por?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          persona_id?: string
          indicador?: string
          tarea_id?: string | null
          fase_id?: string | null
          motivo?: string
          estado?: string
          excluir?: boolean
          respuesta?: string | null
          resuelta_por?: string | null
          resuelta_en?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "solicitud_correccion_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "solicitud_correccion_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "solicitud_correccion_resuelta_por_fkey"; columns: ["resuelta_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "solicitud_correccion_tarea_id_fkey"; columns: ["tarea_id"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] }
        ]
      }
      tarea_diseno: {
        Row: {
          id: string
          proyecto_id: string
          fase_id: string | null
          titulo: string
          descripcion: string | null
          asignada_a: string
          asignada_por: string
          objetivo_id: string | null
          bloqueada_por: string | null
          estado: Database["public"]["Enums"]["estado_tarea"]
          fecha_inicio: string | null
          fecha_compromiso: string | null
          terminada_en: string | null
          creada_en: string
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"]
          plantilla_tarea_id: string | null
          proposito: string | null
          espacio: string | null
          revision_pedida_en: string | null
          dias_estimados: number | null
          requiere_revision: boolean
          revisor_id: string | null
        }
        Insert: {
          id?: string
          proyecto_id: string
          fase_id?: string | null
          titulo: string
          descripcion?: string | null
          asignada_a: string
          asignada_por: string
          objetivo_id?: string | null
          bloqueada_por?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          fecha_inicio?: string | null
          fecha_compromiso?: string | null
          terminada_en?: string | null
          creada_en?: string
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          plantilla_tarea_id?: string | null
          proposito?: string | null
          espacio?: string | null
          revision_pedida_en?: string | null
          dias_estimados?: number | null
          requiere_revision?: boolean
          revisor_id?: string | null
        }
        Update: {
          id?: string
          proyecto_id?: string
          fase_id?: string | null
          titulo?: string
          descripcion?: string | null
          asignada_a?: string
          asignada_por?: string
          objetivo_id?: string | null
          bloqueada_por?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          fecha_inicio?: string | null
          fecha_compromiso?: string | null
          terminada_en?: string | null
          creada_en?: string
          prioridad?: Database["public"]["Enums"]["prioridad_pendiente"]
          plantilla_tarea_id?: string | null
          proposito?: string | null
          espacio?: string | null
          revision_pedida_en?: string | null
          dias_estimados?: number | null
          requiere_revision?: boolean
          revisor_id?: string | null
        }
        Relationships: [
          { foreignKeyName: "tarea_diseno_asignada_a_fkey"; columns: ["asignada_a"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_asignada_por_fkey"; columns: ["asignada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_bloqueada_por_fkey"; columns: ["bloqueada_por"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_fase_id_fkey"; columns: ["fase_id"]; isOneToOne: false; referencedRelation: "proyecto_fase"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_objetivo_id_fkey"; columns: ["objetivo_id"]; isOneToOne: false; referencedRelation: "objetivo"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_plantilla_tarea_id_fkey"; columns: ["plantilla_tarea_id"]; isOneToOne: false; referencedRelation: "plantilla_tarea"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_proyecto_id_fkey"; columns: ["proyecto_id"]; isOneToOne: false; referencedRelation: "proyecto"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_diseno_revisor_id_fkey"; columns: ["revisor_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      tarea_evento: {
        Row: {
          id: number
          tarea_id: string
          tipo: string
          de: string | null
          a: string | null
          persona_id: string | null
          ocurrio_en: string
        }
        Insert: {
          id?: number
          tarea_id: string
          tipo: string
          de?: string | null
          a?: string | null
          persona_id?: string | null
          ocurrio_en?: string
        }
        Update: {
          id?: number
          tarea_id?: string
          tipo?: string
          de?: string | null
          a?: string | null
          persona_id?: string | null
          ocurrio_en?: string
        }
        Relationships: [
          { foreignKeyName: "tarea_evento_persona_id_fkey"; columns: ["persona_id"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] },
          { foreignKeyName: "tarea_evento_tarea_id_fkey"; columns: ["tarea_id"]; isOneToOne: false; referencedRelation: "tarea_diseno"; referencedColumns: ["id"] }
        ]
      }
      tarifa_diseno: {
        Row: {
          id: string
          unidad: Database["public"]["Enums"]["unidad_negocio"]
          area_desde: number
          area_hasta: number
          valor: number
          alcance: string | null
          activa: boolean
          creada_por: string | null
          creada_en: string
        }
        Insert: {
          id?: string
          unidad: Database["public"]["Enums"]["unidad_negocio"]
          area_desde: number
          area_hasta: number
          valor: number
          alcance?: string | null
          activa?: boolean
          creada_por?: string | null
          creada_en?: string
        }
        Update: {
          id?: string
          unidad?: Database["public"]["Enums"]["unidad_negocio"]
          area_desde?: number
          area_hasta?: number
          valor?: number
          alcance?: string | null
          activa?: boolean
          creada_por?: string | null
          creada_en?: string
        }
        Relationships: [
          { foreignKeyName: "tarifa_diseno_creada_por_fkey"; columns: ["creada_por"]; isOneToOne: false; referencedRelation: "persona"; referencedColumns: ["id"] }
        ]
      }
      variante_chequeo: {
        Row: {
          id: string
          nombre: string
          descripcion: string | null
          activa: boolean
          creada_en: string
        }
        Insert: {
          id?: string
          nombre: string
          descripcion?: string | null
          activa?: boolean
          creada_en?: string
        }
        Update: {
          id?: string
          nombre?: string
          descripcion?: string | null
          activa?: boolean
          creada_en?: string
        }
        Relationships: []
      }
    }
    Views: {
      v_adicionales_netos: {
        Row: {
          proyecto_id: string | null
          proyecto: string | null
          cantidad: number | null
          aprobados: number | null
          pendientes: number | null
          rechazados: number | null
          bruto: number | null
          credito: number | null
          neto: number | null
          bruto_aprobado: number | null
          a_cargo_cliente: number | null
          a_cargo_esa: number | null
        }
        Relationships: []
      }
      v_apu_costo: {
        Row: {
          apu_id: string | null
          codigo: string | null
          descripcion: string | null
          unidad: string | null
          costo_unitario: number | null
          componentes: number | null
          precio_mas_reciente: string | null
        }
        Relationships: []
      }
      v_balance_centro_costo: {
        Row: {
          centro_costo_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          categoria: string | null
          excluir_de_rentabilidad: boolean | null
          presupuesto: number | null
          comprometido: number | null
          causado: number | null
          pagado: number | null
          proyectado: number | null
          por_pagar: number | null
          disponible: number | null
        }
        Relationships: []
      }
      v_bitacora_faltante: {
        Row: {
          proyecto_id: string | null
          proyecto: string | null
          residente_id: string | null
          fecha: string | null
        }
        Relationships: []
      }
      v_caja_menor: {
        Row: {
          fondo_id: string | null
          responsable_id: string | null
          responsable: string | null
          entregado_por_id: string | null
          entregado_por: string | null
          entregado: number | null
          fecha_entrega: string | null
          legalizado_en: string | null
          gastado: number | null
          saldo: number | null
          gastos_sin_soporte: number | null
          dias_abierto: number | null
        }
        Relationships: []
      }
      v_calibracion_capitulo: {
        Row: {
          capitulo: string | null
          proyectos: number | null
          items_medidos: number | null
          presupuestado: number | null
          a_precio_de_contrato: number | null
          factor_cantidad: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_cambios_sin_reflejar: {
        Row: {
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          fecha: string | null
          descripcion: string | null
          decidido_por: string | null
          dias_abierto: number | null
          genera_adicional: boolean | null
        }
        Relationships: []
      }
      v_capacidad_13_semanas: {
        Row: {
          horas_disponibles: number | null
          horas_comprometidas: number | null
          holgura: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_carga_equipo: {
        Row: {
          persona_id: string | null
          nombre: string | null
          rol: Database["public"]["Enums"]["rol_persona"] | null
          abiertas: number | null
          vencidas: number | null
          sin_fecha: number | null
          esta_semana: number | null
          esperando_revision: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_cartera: {
        Row: {
          acta_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          cliente: string | null
          numero: string | null
          emitida_en: string | null
          vence_en: string | null
          valor_a_cobrar: number | null
          valor_retenido: number | null
          recaudado: number | null
          saldo: number | null
          dias_vencida: number | null
          antiguedad: string | null
        }
        Relationships: []
      }
      v_cola_revision: {
        Row: {
          tarea_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          titulo: string | null
          persona_id: string | null
          persona: string | null
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"] | null
          fecha_compromiso: string | null
          revision_pedida_en: string | null
          dias_habiles_esperando: number | null
          fuera_de_plazo: boolean | null
          devoluciones: number | null
          lectura: string | null
          revisor_id: string | null
        }
        Relationships: []
      }
      v_complementarios_atrasados: {
        Row: {
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          especialidad: Database["public"]["Enums"]["especialidad"] | null
          profesional: string | null
          fecha_compromiso: string | null
          dias_atraso: number | null
          estado: Database["public"]["Enums"]["estado_complementario"] | null
        }
        Relationships: []
      }
      v_dedicacion_pendiente: {
        Row: {
          persona_id: string | null
          nombre: string | null
          fecha: string | null
        }
        Relationships: []
      }
      v_desviacion_capitulo: {
        Row: {
          capitulo_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          capitulo: string | null
          presupuestado: number | null
          proyectado: number | null
          desviacion: number | null
          desviacion_pct: number | null
          avance_valorizado: number | null
        }
        Relationships: []
      }
      v_embudo_mensual: {
        Row: {
          mes: string | null
          canal: Database["public"]["Enums"]["canal_origen"] | null
          leads: number | null
          contactados: number | null
          minutos_primera_respuesta: number | null
          oportunidades: number | null
          citas_realizadas: number | null
          no_shows: number | null
          ganadas: number | null
          perdidas: number | null
          en_nutricion: number | null
          descartados: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_embudo_ventas: {
        Row: {
          linea: string | null
          etapa: Database["public"]["Enums"]["etapa_oportunidad"] | null
          oportunidades: number | null
          valor: number | null
          atrasadas: number | null
          dias_promedio: number | null
        }
        Relationships: []
      }
      v_fase_avance: {
        Row: {
          fase_id: string | null
          proyecto_id: string | null
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          estado: Database["public"]["Enums"]["estado_fase"] | null
          tareas: number | null
          terminadas: number | null
          trabajo_terminado: boolean | null
        }
        Relationships: []
      }
      v_fase_horas: {
        Row: {
          fase_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          estado: Database["public"]["Enums"]["estado_fase"] | null
          horas_cotizadas: number | null
          horas_reales: number | null
          pct_consumido: number | null
          sobre_dedicacion: boolean | null
          lectura: string | null
        }
        Relationships: []
      }
      v_flujo_13_semanas: {
        Row: {
          semana: number | null
          desde: string | null
          hasta: string | null
          entradas: number | null
          salidas: number | null
          saldo_final: number | null
          bajo_minimo: boolean | null
          saldo_tomado_el: string | null
        }
        Relationships: []
      }
      v_mi_dia: {
        Row: {
          origen: string | null
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          titulo: string | null
          estado: string | null
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"] | null
          fecha_compromiso: string | null
          orden: number | null
          grupo: string | null
          espera_a: string | null
          frena_a: string | null
          para_que: string | null
          lectura: string | null
        }
        Relationships: []
      }
      v_movimiento_vigente: {
        Row: {
          id: string | null
          consecutivo: number | null
          proyecto_id: string | null
          centro_costo_id: string | null
          estado: Database["public"]["Enums"]["estado_dinero"] | null
          naturaleza: string | null
          fecha: string | null
          valor: number | null
          tercero_id: string | null
          tercero_nombre: string | null
          concepto: string | null
          medio: Database["public"]["Enums"]["medio_pago"] | null
          cuenta_id: string | null
          capitulo_id: string | null
          adicional_id: string | null
          acta_id: string | null
          fondo_id: string | null
          origen_id: string | null
          raiz_id: string | null
          fecha_prevista_pago: string | null
          aprobacion: Database["public"]["Enums"]["estado_aprobacion"] | null
          aprobado_por: string | null
          aprobado_en: string | null
          anula_a: string | null
          motivo_anulacion: string | null
          registrado_por: string | null
          registrado_en: string | null
          sincronizado_en: string | null
          conciliado: boolean | null
          conciliado_en: string | null
          numero_factura: string | null
        }
        Relationships: []
      }
      v_objetivos: {
        Row: {
          id: string | null
          ambito: Database["public"]["Enums"]["ambito_objetivo"] | null
          proyecto_id: string | null
          proyecto: string | null
          persona_id: string | null
          titulo: string | null
          estado: Database["public"]["Enums"]["estado_objetivo"] | null
          fecha_limite: string | null
          responsable: string | null
          responsable_id: string | null
          total: number | null
          hechas: number | null
          atrasadas: number | null
          pasado_de_fecha: boolean | null
          lectura: string | null
        }
        Relationships: []
      }
      v_obra_flujo_mes: {
        Row: {
          proyecto_id: string | null
          mes: string | null
          pagado: number | null
          pagos: number | null
          cobrado: number | null
        }
        Relationships: []
      }
      v_obra_por_pagar: {
        Row: {
          raiz_id: string | null
          proyecto_id: string | null
          centro_costo_id: string | null
          categoria: string | null
          tercero: string | null
          concepto: string | null
          fecha: string | null
          aprobacion: Database["public"]["Enums"]["estado_aprobacion"] | null
          numero_factura: string | null
          facturado: boolean | null
          total: number | null
          pagado: number | null
          por_pagar: number | null
          fecha_prevista: string | null
        }
        Relationships: []
      }
      v_obra_tablero: {
        Row: {
          id: string | null
          codigo: string | null
          nombre: string | null
          estado: Database["public"]["Enums"]["estado_proyecto"] | null
          unidad: Database["public"]["Enums"]["unidad_negocio"] | null
          carpeta_drive: string | null
          valor_contrato: number | null
          fecha_inicio: string | null
          fecha_fin_prevista: string | null
          residente_id: string | null
          residente: string | null
          costo_proyectado: number | null
          pagado: number | null
          por_pagar: number | null
          cobrado: number | null
          gastos_por_aprobar: number | null
          valor_por_aprobar: number | null
          pendientes_abiertos: number | null
          pendientes_vencidos: number | null
          pendientes_por_verificar: number | null
          dias_sin_bitacora: number | null
          ultima_bitacora: string | null
          adicionales_pendientes: number | null
          ultimo_gasto: string | null
          documentos: number | null
          pct_contrato: number | null
          lectura: string | null
          alerta: string | null
        }
        Relationships: []
      }
      v_partidas_abiertas: {
        Row: {
          id: string | null
          cuenta_id: string | null
          cuenta: string | null
          fecha: string | null
          valor: number | null
          descripcion: string | null
          responsable_id: string | null
          responsable: string | null
          dias_abierta: number | null
        }
        Relationships: []
      }
      v_pendientes_obra: {
        Row: {
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          titulo: string | null
          ubicacion: string | null
          tipo: Database["public"]["Enums"]["tipo_pendiente"] | null
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"] | null
          estado: Database["public"]["Enums"]["estado_pendiente"] | null
          responsable: string | null
          responsable_id: string | null
          ejecutor: string | null
          fecha_compromiso: string | null
          dias_atraso: number | null
          espera_a: string | null
          tiene_gasto: boolean | null
          lectura: string | null
        }
        Relationships: []
      }
      v_proyecto_resumen: {
        Row: {
          id: string | null
          codigo: string | null
          nombre: string | null
          unidad: Database["public"]["Enums"]["unidad_negocio"] | null
          tipo: Database["public"]["Enums"]["tipo_proyecto"] | null
          estado: Database["public"]["Enums"]["estado_proyecto"] | null
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          es_reclamacion: boolean | null
          canal: Database["public"]["Enums"]["canal_origen"] | null
          valor_contrato: number | null
          costo_proyectado: number | null
          por_pagar: number | null
          presupuesto_obra: number | null
          obra_proyectada: number | null
          adicional_neto: number | null
          adicionales_pendientes: number | null
          desviacion_pct: number | null
          margen_proyectado_pct: number | null
        }
        Relationships: []
      }
      v_reclamaciones: {
        Row: {
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          empresa_asegurada: string | null
          aseguradora: string | null
          oficina_abogados: string | null
          numero_poliza: string | null
          estado: Database["public"]["Enums"]["estado_reclamacion"] | null
          fecha_limite: string | null
          dias_para_vencer: number | null
          dias_en_estado: number | null
          puntos_obligatorios: number | null
          puntos_cumplidos: number | null
          checklist_completo: boolean | null
          conciliada_con_abogados: boolean | null
          con_aval_estructural: boolean | null
          valor_reclamado: number | null
          valor_aprobado: number | null
        }
        Relationships: []
      }
      v_rentabilidad_proyecto: {
        Row: {
          proyecto_id: string | null
          codigo: string | null
          nombre: string | null
          unidad: Database["public"]["Enums"]["unidad_negocio"] | null
          tipo: Database["public"]["Enums"]["tipo_proyecto"] | null
          estado: Database["public"]["Enums"]["estado_proyecto"] | null
          canal: Database["public"]["Enums"]["canal_origen"] | null
          valor_contrato: number | null
          ingresos: number | null
          costo_pagado: number | null
          costo_proyectado: number | null
          estructura_asignada: number | null
          meta: number | null
          margen_bruto: number | null
          margen_neto: number | null
          margen_neto_pct: number | null
          bajo_meta: boolean | null
          lectura: string | null
        }
        Relationships: []
      }
      v_retorno_pauta: {
        Row: {
          campana_id: string | null
          campana: string | null
          canal: Database["public"]["Enums"]["canal_origen"] | null
          mes: string | null
          inversion: number | null
          ventas_cerradas: number | null
          venta: number | null
          venta_por_peso: number | null
          costo_adquisicion_pct: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_ritmo_ventas: {
        Row: {
          citas_viabilidad: number | null
          no_llegaron: number | null
          presentaciones: number | null
          ventas: number | null
          valor_ventas: number | null
          citas_por_mes: number | null
          citas_por_venta: number | null
          citas_para_la_meta: number | null
          lectura: string | null
        }
        Relationships: []
      }
      v_tarea_contexto: {
        Row: {
          tarea_id: string | null
          proyecto_id: string | null
          proyecto: string | null
          fase: Database["public"]["Enums"]["fase_proyecto"] | null
          entrega_cliente: string | null
          proposito: string | null
          objetivo: string | null
          espera_titulo: string | null
          espera_a: string | null
          la_esperan: string | null
          para_que: string | null
        }
        Relationships: []
      }
      v_trabajo_abierto: {
        Row: {
          origen: string | null
          id: string | null
          proyecto_id: string | null
          proyecto: string | null
          titulo: string | null
          persona_id: string | null
          persona: string | null
          estado: string | null
          fecha_compromiso: string | null
          dias_atraso: number | null
          objetivo_id: string | null
        }
        Relationships: []
      }
      v_ventas_hoy: {
        Row: {
          persona_id: string | null
          orden: number | null
          que: string | null
          lead_id: string | null
          oportunidad_id: string | null
          cita_id: string | null
          nombre: string | null
          lectura: string | null
          urgente: boolean | null
        }
        Relationships: []
      }
    }
    Functions: {
      abrir_chequeo: {
        Args: {
          p_fase: string
        }
        Returns: string
      }
      abrir_proyecto: {
        Args: {
          p_codigo: string
          p_nombre: string
          p_plantilla: string
          p_unidad: Database["public"]["Enums"]["unidad_negocio"]
          p_horas?: Json
          p_equipo?: Json
          p_variante?: string
          p_omitir?: Database["public"]["Enums"]["fase_proyecto"][]
          p_cliente?: string
          p_responsable?: string
        }
        Returns: string
      }
      agendar_cita_de_lead: {
        Args: {
          p_lead: string
          p_datos: Json
        }
        Returns: Json
      }
      aplicar_plantilla: {
        Args: {
          p_proyecto: string
          p_plantilla: string
          p_horas?: Json
          p_variante?: string
          p_omitir?: Database["public"]["Enums"]["fase_proyecto"][]
        }
        Returns: number
      }
      carga_semanal: {
        Args: {
          p_semanas?: number
          p_desde?: string
        }
        Returns: {
          persona_id: string
          nombre: string
          semana: string
          dias_habiles: number
          dias_ocupados: number
          tareas: number
          sin_estimar: number
          vencidas: number
        }[]
      }
      crear_tareas: {
        Args: {
          p_fase: string
          p_tareas: Json
        }
        Returns: number
      }
      distribuir_estructura: {
        Args: {
          p_periodo: string
        }
        Returns: number
      }
      falta_para_cerrar: {
        Args: {
          p_fase: string
        }
        Returns: {
          orden: number
          que: string
          listo: boolean
          bloquea: boolean
          detalle: string
        }[]
      }
      indicador_detalle: {
        Args: {
          p_indicador: string
          p_persona?: string
          p_hasta?: string
        }
        Returns: {
          tarea_id: string
          fase_id: string
          proyecto: string
          titulo: string
          hecho: string
          a_favor: boolean
          excluida: boolean
        }[]
      }
      indicadores: {
        Args: {
          p_persona?: string
          p_hasta?: string
        }
        Returns: {
          orden: number
          indicador: string
          titulo: string
          numerador: number
          denominador: number
          suficiente: boolean
          frase: string
        }[]
      }
      mi_sesion: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      nuevo_contacto: {
        Args: {
          p_datos: Json
        }
        Returns: Json
      }
      proponer_tareas: {
        Args: {
          p_fase: string
          p_espacios?: string[]
        }
        Returns: {
          plantilla_tarea_id: string
          orden: number
          titulo: string
          espacio: string
          proposito: string
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"]
          fecha_sugerida: string
          depende_de: string
        }[]
      }
      punto_de_cierre: {
        Args: {
          p_plantilla_fase: string
          p_texto: string
          p_tipo?: string
          p_opciones?: string[]
          p_obligatorio?: boolean
        }
        Returns: string
      }
      reasignar_tareas: {
        Args: {
          p_de: string
          p_a: string
          p_proyecto?: string
        }
        Returns: number
      }
      registrar_gasto: {
        Args: {
          p_datos: Json
        }
        Returns: string
      }
      reporte_de_cita: {
        Args: {
          p_cita: string
          p_datos: Json
        }
        Returns: string
      }
      tareas_tipicas: {
        Args: {
          p_fase: string
          p_espacios?: string[]
        }
        Returns: {
          plantilla_tarea_id: string
          orden: number
          titulo: string
          espacio: string
          proposito: string
          prioridad: Database["public"]["Enums"]["prioridad_pendiente"]
          fecha_sugerida: string
          depende_de: string
          dias_estimados: number
          por_espacio: boolean
        }[]
      }
      valor_sugerido: {
        Args: {
          p_unidad: Database["public"]["Enums"]["unidad_negocio"]
          p_area: number
        }
        Returns: number
      }
    }
    Enums: {
      ambito_chequeo: "fase_diseno" | "radicacion_licencia" | "reclamacion" | "presupuesto"
      ambito_objetivo: "empresa" | "proyecto" | "persona"
      bloque_dia: "manana" | "tarde"
      canal_aviso: "plataforma" | "correo" | "sms"
      canal_origen: "google_ads" | "referido" | "cliente_recurrente" | "instagram_organico" | "meta_ads" | "youtube" | "linkedin" | "web_organico" | "asistente_ia" | "whatsapp_directo" | "otro"
      especialidad: "estructural" | "hidrosanitario" | "electrico" | "suelos" | "topografia" | "otro"
      estado_aprobacion: "no_requiere" | "pendiente" | "aprobado" | "rechazado"
      estado_aviso: "pendiente" | "enviado" | "fallido" | "descartado"
      estado_cita: "agendada" | "realizada" | "no_show" | "reprogramada" | "cancelada"
      estado_complementario: "por_contratar" | "contratado" | "en_curso" | "entregado" | "aprobado"
      estado_cotizacion: "borrador" | "emitida" | "aceptada" | "rechazada" | "vencida" | "reemplazada"
      estado_dinero: "compromiso" | "causacion" | "pago"
      estado_experimento: "planeado" | "corriendo" | "cerrado"
      estado_fase: "pendiente" | "en_curso" | "en_revision" | "cerrada"
      estado_lead: "nuevo" | "contactado" | "calificado" | "nutricion" | "descartado" | "convertido"
      estado_objetivo: "en_curso" | "logrado" | "no_logrado" | "cancelado"
      estado_pendiente: "abierto" | "en_ejecucion" | "por_verificar" | "cerrado" | "descartado"
      estado_presupuesto: "borrador" | "en_validacion" | "validado" | "emitido" | "aprobado_cliente" | "reemplazado"
      estado_proyecto: "prospecto" | "activo" | "pausado" | "terminado" | "cancelado"
      estado_radicacion: "preparacion" | "radicada" | "con_observaciones" | "aprobada" | "negada"
      estado_reclamacion: "en_expediente" | "conciliada" | "radicada" | "objetada" | "aprobada" | "pagada_a_asegurado" | "pagada_a_abogados" | "pagada_a_esa" | "negada" | "desistida"
      estado_tarea: "asignada" | "en_curso" | "en_revision" | "con_observaciones" | "terminada"
      etapa_oportunidad: "cita_viabilidad" | "presupuesto_detallado" | "cotizacion_enviada" | "negociacion" | "ganada" | "perdida"
      fase_proyecto: "insight" | "anteproyecto" | "proyecto_final" | "licencia" | "presupuesto" | "obra" | "cierre" | "levantamiento" | "informe" | "entrega_expediente" | "preconstruccion" | "ejecucion"
      linea_servicio: "consultoria" | "arquitectura" | "obra_civil" | "interiorismo" | "peritaje" | "otros_ingresos" | "traslado_entre_cuentas" | "credito_bancario"
      medio_contacto: "whatsapp" | "llamada" | "correo" | "formulario_web" | "presencial" | "otro"
      medio_pago: "banco" | "efectivo" | "tarjeta" | "credito" | "no_aplica"
      motivo_perdida: "precio" | "tiempo" | "competencia" | "desaparecio" | "sin_capacidad_pago" | "no_calificado" | "aplazado" | "otro"
      nivel_acceso: "lectura" | "registro" | "aprobacion" | "total"
      papel_proyecto: "dirige" | "produce" | "revisa" | "observa"
      prioridad_pendiente: "normal" | "alta" | "bloqueante"
      rol_persona: "socio" | "director" | "arquitecto" | "practicante" | "residente" | "mercadeo" | "financiero" | "contratista" | "proveedor" | "cliente" | "profesional_externo" | "aseguradora" | "abogado" | "sin_clasificar" | "director_proyecto"
      severidad: "critico" | "alerta" | "informativo"
      tipo_acta: "cobro_cliente" | "pago_contratista"
      tipo_cuenta: "banco" | "efectivo" | "tarjeta_credito"
      tipo_insumo: "material" | "mano_obra" | "equipo" | "transporte" | "subcontrato"
      tipo_pendiente: "ejecucion" | "tramite" | "revision" | "compra"
      tipo_proyecto: "diseno" | "obra" | "consultoria" | "peritaje" | "interno"
      unidad_negocio: "diseno_arquitectonico" | "interiorismo" | "consultoria" | "obra_propia" | "obra_colega" | "peritaje" | "administracion"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type EsquemaPublico = Database["public"]
export type Tabla<T extends keyof EsquemaPublico["Tables"]> = EsquemaPublico["Tables"][T]["Row"]
export type Vista<T extends keyof EsquemaPublico["Views"]> = EsquemaPublico["Views"][T]["Row"]
export type Enum<T extends keyof EsquemaPublico["Enums"]> = EsquemaPublico["Enums"][T]
export type Funcion<T extends keyof EsquemaPublico["Functions"]> = EsquemaPublico["Functions"][T]
