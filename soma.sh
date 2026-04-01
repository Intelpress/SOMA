#!/bin/bash
# =============================================================================
# SOMA — Sistema de Orientación de Memoria Activa
# -----------------------------------------------------------------------------
# SOMA no es un asistente genérico. Es un agente personal con identidad,
# memoria y criterio. Actúa bajo el principio de Sinapsis Supervisada:
# ninguna escritura al vault ocurre sin confirmación explícita del usuario.
#
# Autor:   Juan José Arellano (@jkukuriku) — intelpress.4.0@gmail.com
# Versión: 0.4.1 — 2026-03-29 (corregida)
# Stack:   Bash + curl + jq + lynx + Groq API + OpenRouter (fallback)
# Vault:   ~/vault/SOMA/
# Config:  ~/.config/groq/
#
# FLAGS (14):
#   --web                búsqueda web en lenguaje natural (compound-beta)
#   --extraer  / --ext   extrae contenido de URL
#   --buscar   / --bus   escanea vault por término
#   --conectar / --con   inyecta texto desde pipe (stdin)
#   --unir     / --uni   inyecta uno o varios archivos como contexto
#   --guardar  / --gua   guarda respuesta en vault (05_Salida)
#   --registrar/ --reg   escribe archivo supervisado en ruta específica
#   --cerrar   / --cer   genera documento de cierre de sesión
#   --reiniciar/ --rei   limpia historial de conversación
#   --resumir  / --res   resume historial actual sin cerrarlo
#   --recordar / --rec   carga el último cierre de sesión como contexto
#   --modo     / --mod   cambia perfil activo
#   --proyecto / --pro   inyecta contexto de proyecto
#   --ayuda    / --ayu   muestra esta ayuda
# =============================================================================

# --- CONFIGURACIÓN ---
DIR="$HOME/.config/groq"
PROFILE_DIR="$DIR/profiles"
HISTORY="$DIR/soma_history.json"
USER_JSON="$DIR/usuario.json"
VAULT_SOMA="$HOME/vault/SOMA"
VAULT_ZAF="$HOME/vault/ZAF"
MAX_HISTORY=10
AGENT_MODE="soma"
PROYECTO_ACTIVO=""

# OpenRouter fallback
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
GROQ_FALLBACK_MODELS=(
    "moonshotai/kimi-k2-instruct"
    "meta-llama/llama-4-scout-17b-16e-instruct"
    "qwen/qwen3-32b"
)
                                                   
OPENROUTER_MODELS=(
    "nvidia/nemotron-3-super-120b-a12b:free"
    "meta-llama/llama-3.3-70b-instruct:free"
    "openai/gpt-oss-120b:free"
)

OPENROUTER_URL="https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_MODEL="${OPENROUTER_MODELS[0]}"  

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

validar_deps() {
    local faltantes=()
    for cmd in curl jq lynx; do
        command -v "$cmd" &>/dev/null || faltantes+=("$cmd")
    done
    if [[ ${#faltantes[@]} -gt 0 ]]; then
        echo "[SOMA] Error: dependencias faltantes: ${faltantes[*]}"
        echo "       Instala con: sudo apt install ${faltantes[*]}"
        exit 1
    fi
}

llamar_api() {
    local messages="$1"
    local model="$2"
    local temp="$3"

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(jq -nc \
            --arg m "$model" \
            --argjson msgs "$messages" \
            --argjson t "$temp" \
            '{model: $m, messages: $msgs, temperature: $t}')")

    local http_status body
    http_status=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_status" -eq 200 ]]; then
        echo "$body"
        return 0
    fi

    local err_msg
    err_msg=$(echo "$body" | jq -r '.error.message // "Error desconocido"')
# Cascade Groq alternativo antes de OpenRouter
    for GROQ_FALLBACK in "${GROQ_FALLBACK_MODELS[@]}"; do
        echo "[SOMA] Groq no disponible ($http_status: $err_msg). Intentando Groq fallback ($GROQ_FALLBACK)..." >&2
        response=$(curl -s -w "\n%{http_code}" \
            -X POST "https://api.groq.com/openai/v1/chat/completions" \
            -H "Authorization: Bearer $GROQ_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$(jq -nc \
                --arg m "$GROQ_FALLBACK" \
                --argjson msgs "$messages" \
                --argjson t "$temp" \
                '{model: $m, messages: $msgs, temperature: $t}')")
        http_status=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        if [[ "$http_status" -eq 200 ]]; then
            echo "$body"
            return 0
        fi
        err_msg=$(echo "$body" | jq -r '.error.message // "Error desconocido"')
        echo "[SOMA] $GROQ_FALLBACK no disponible ($http_status: $err_msg). Probando siguiente..." >&2
    done

    if [[ -n "$OPENROUTER_API_KEY" ]]; then
        for OPENROUTER_MODEL in "${OPENROUTER_MODELS[@]}"; do
            echo "[SOMA] Intentando OpenRouter ($OPENROUTER_MODEL)..." >&2
            response=$(curl -s -w "\n%{http_code}" \
                -X POST "$OPENROUTER_URL" \
                -H "Authorization: Bearer $OPENROUTER_API_KEY" \
                -H "Content-Type: application/json" \
                -H "X-Title: SOMA" \
                -d "$(jq -nc \
                    --arg m "$OPENROUTER_MODEL" \
                    --argjson msgs "$messages" \
                    --argjson t "$temp" \
                    '{model: $m, messages: $msgs, temperature: $t}')")
            http_status=$(echo "$response" | tail -n1)
            body=$(echo "$response" | sed '$d')
            if [[ "$http_status" -eq 200 ]]; then
                echo "$body"
                return 0
            fi
            err_msg=$(echo "$body" | jq -r '.error.message // "Error desconocido"')
            echo "[SOMA] $OPENROUTER_MODEL no disponible ($http_status: $err_msg). Probando siguiente..." >&2
            sleep 5
        done
    fi
    echo "[SOMA] Error API ($http_status): $err_msg" >&2
    return 1
}

# Escritura supervisada — nunca escribe sin confirmación explícita
guardar_en_vault() {
    local ruta="$1"
    local contenido="$2"
    local descripcion="${3:-archivo}"

    echo ""
    echo "[SOMA] ¿Guardar $descripcion en vault?"
    echo "       Ruta: $ruta"
    echo -n "       Confirmar [S/n]: "
    read -r confirm < /dev/tty
    if [[ -z "$confirm" || "$confirm" =~ ^[sS]$ ]]; then
        mkdir -p "$(dirname "$ruta")"
        printf '%s' "$contenido" > "$ruta"
        echo "[SOMA] Guardado: $ruta"
    else
        echo "[SOMA] Cancelado. No se escribió al vault."
    fi
}

actualizar_historial() {
    local user_input="$1"
    local ai_text="$2"
    local user_log ai_log
    user_log=$(jq -nc --arg c "$user_input" '{role: "user", content: $c}')
    ai_log=$(jq -nc --arg c "$ai_text" '{role: "assistant", content: $c}')
    jq ". += [$user_log, $ai_log] | .[-$MAX_HISTORY:]" "$HISTORY" > "$HISTORY.tmp" \
        && mv -- "$HISTORY.tmp" "$HISTORY"
}

# =============================================================================
# VALIDACIONES INICIALES
# =============================================================================

validar_deps

if [[ -z "$GROQ_API_KEY" ]]; then
    echo "[SOMA] Error: GROQ_API_KEY no definida."
    exit 1
fi

if [[ ! -f "$PROFILE_DIR/soma.json" ]]; then
    echo "[SOMA] Error: profiles/soma.json no encontrado."
    exit 1
fi

if [[ ! -f "$USER_JSON" ]]; then
    echo "[SOMA] Error: usuario.json no encontrado."
    exit 1
fi

mkdir -p "$PROFILE_DIR"
[[ ! -f "$HISTORY" || ! -s "$HISTORY" ]] && echo "[]" > "$HISTORY"

# =============================================================================
# PARSEO DE FLAGS (CORREGIDO)
# =============================================================================

WEB_QUERY=""
EXTRAER_URL=""
BUSCAR_TERM=""
BUSCAR_PATH=""
CONECTAR=false
ARCHIVOS_UNIR=()
SAVE=false
REGISTRAR_RUTA=""
CERRAR=false
REINICIAR=false
RESUMIR=false
RECORDAR=false
INPUT_ORIGINAL=""

ARGS=("$@")
IDX=0
while [[ $IDX -lt ${#ARGS[@]} ]]; do
    arg="${ARGS[$IDX]}"
    case "$arg" in
        --modo|--mod)
            IDX=$(( IDX + 1 ))
            AGENT_MODE="${ARGS[$IDX]}"
            IDX=$(( IDX + 1 ))
            ;;
        --proyecto|--pro)
            IDX=$(( IDX + 1 ))
            PROYECTO_ACTIVO="${ARGS[$IDX]}"
            IDX=$(( IDX + 1 ))
            ;;
        --web)
            IDX=$(( IDX + 1 ))
            WEB_QUERY=""
            while [[ $IDX -lt ${#ARGS[@]} && "${ARGS[$IDX]}" != --* ]]; do
                WEB_QUERY="${WEB_QUERY:+$WEB_QUERY }${ARGS[$IDX]}"
                IDX=$(( IDX + 1 ))
            done
            ;;
        --extraer|--ext)
            IDX=$(( IDX + 1 ))
            EXTRAER_URL="${ARGS[$IDX]}"
            IDX=$(( IDX + 1 ))
            ;;
        --buscar|--bus)
            IDX=$(( IDX + 1 ))
            BUSCAR_TERM=""
            BUSCAR_PATH=""
            if [[ $IDX -lt ${#ARGS[@]} && "${ARGS[$IDX]}" != --* ]]; then
                if [[ "${ARGS[$IDX]}" == /* || "${ARGS[$IDX]}" == ~* || "${ARGS[$IDX]}" == ./* ]]; then
                    BUSCAR_PATH="${ARGS[$IDX]}"
                else
                    BUSCAR_TERM="${ARGS[$IDX]}"
					fi
					IDX=$(( IDX + 1 ))
            fi
            ;;
        --conectar|--con)
            CONECTAR=true
            IDX=$(( IDX + 1 ))
            ;;
        --unir|--uni)
            IDX=$(( IDX + 1 ))
            while [[ $IDX -lt ${#ARGS[@]} && "${ARGS[$IDX]}" != --* ]]; do
                arg_actual="${ARGS[$IDX]}"
                if [[ -f "$arg_actual" || "$arg_actual" == /* || "$arg_actual" == ~* || "$arg_actual" == ./* ]]; then
                    ARCHIVOS_UNIR+=("$arg_actual")
                    IDX=$(( IDX + 1 ))
				else
					QUERY_LIBRE="${ARGS[$IDX]}"
					IDX=$(( IDX + 1 ))
					break
				fi
			done
            ;;
        --guardar|--gua)
            SAVE=true
            IDX=$(( IDX + 1 ))
            ;;
        --registrar|--reg)
            IDX=$(( IDX + 1 ))
            REGISTRAR_RUTA="${ARGS[$IDX]}"
            IDX=$(( IDX + 1 ))
            ;;
        --cerrar|--cer)
            CERRAR=true
            IDX=$(( IDX + 1 ))
            ;;
        --reiniciar|--rei)
            REINICIAR=true
            IDX=$(( IDX + 1 ))
            ;;
        --resumir|--res)
            RESUMIR=true
            IDX=$(( IDX + 1 ))
            ;;
        --recordar|--rec)
            RECORDAR=true
            IDX=$(( IDX + 1 ))
            ;;
        --ayuda|--ayu|--help)
            echo ""
            echo "SOMA — Sistema de Orientación y Memoria Activa v0.4.1"
            echo ""
            echo "Uso: soma [flags] 'consulta'"
            echo ""
            echo "  Flag completo    Alias  Función"
            echo "  ─────────────────────────────────────────────────────────────────"
            echo "  --web            --web  Búsqueda web en lenguaje natural"
            echo "  --extraer URL    --ext  Extrae contenido de una URL"
            echo "  --buscar TERM    --bus  Escanea vault por término"
            echo "  --conectar       --con  Inyecta texto desde pipe (stdin)"
            echo "  --unir ARCH...   --uni  Inyecta uno o varios archivos como contexto"
            echo "  --guardar        --gua  Guarda respuesta en 05_Salida/"
            echo "  --registrar RUTA --reg  Escribe archivo supervisado en ruta específica"
            echo "  --cerrar         --cer  Genera documento de cierre de sesión"
            echo "  --reiniciar      --rei  Limpia historial de conversación"
            echo "  --resumir        --res  Resume historial actual sin cerrarlo"
            echo "  --recordar       --rec  Carga el último cierre de sesión como contexto"
            echo "  --modo PERFIL    --mod  Cambia perfil activo"
            echo "  --proyecto NOMBRE--pro  Inyecta contexto de proyecto"
            echo "  --ayuda          --ayu  Muestra esta ayuda"
            echo ""
            echo "Ejemplos:"
            echo "  soma 'qué pendientes tengo'"
            echo "  soma --web qué es compound-beta de Groq"
            echo "  soma --ext 'https://url.com' 'analiza el enfoque'"
            echo "  soma --uni script.py error.log 'por qué falla'"
            echo "  find ~/vault/SOMA -name '*.md' | soma --con 'genera el MOC'"
            echo "  soma --reg 02_Conciencia/mapas/MOC_SOMA.md 'actualiza el MOC'"
            echo ""
            echo "Variables de entorno:"
            echo "  GROQ_API_KEY          (requerida)"
            echo "  OPENROUTER_API_KEY    (opcional, activa fallback automático)"
            echo ""
            exit 0
            ;;
        --*)
            echo "[SOMA] Flag desconocido: $arg"
            echo "       Usa --ayuda para ver opciones disponibles."
            exit 1
            ;;
        *)
            # Se encontró la consulta libre, rompemos el bucle
            break
            ;;
    esac
done

[[ -z "$QUERY_LIBRE" ]] && QUERY_LIBRE="${ARGS[*]:$IDX}"

# =============================================================================
# CARGA DE PERFIL
# =============================================================================

PROFILE_FILE="$PROFILE_DIR/$AGENT_MODE.json"
if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "[SOMA] Error: perfil '$AGENT_MODE.json' no encontrado en $PROFILE_DIR"
    exit 1
fi

SYSTEM_PROMPT=$(jq -r '.system_prompt' "$PROFILE_FILE")
MODEL=$(jq -r '.config.model // "llama-3.3-70b-versatile"' "$PROFILE_FILE")
TEMP=$(jq -r '(.config.temperature // 0.1) | tonumber' "$PROFILE_FILE")
USER_DATA=$(cat "$USER_JSON")

INPUT_ORIGINAL="$QUERY_LIBRE"

# =============================================================================
# --reiniciar: limpia historial
# =============================================================================

if [[ "$REINICIAR" == true ]]; then
    echo "[]" > "$HISTORY"
    echo "[SOMA] Historial reiniciado."
    exit 0
fi

# =============================================================================
# --cerrar: cierre de sesión supervisado
# =============================================================================

if [[ "$CERRAR" == true ]]; then
    echo "[SOMA] Generando documento de cierre de sesión..."

    HISTORY_DATA=$(cat "$HISTORY")
    HISTORY_LEN=$(echo "$HISTORY_DATA" | jq 'length')

    if [[ "$HISTORY_LEN" -eq 0 ]]; then
        echo "[SOMA] No hay historial activo para cerrar."
        exit 0
    fi

    CIERRE_PROMPT="Eres SOMA. Basándote en el historial de esta sesión, genera un documento de cierre con exactamente estas secciones en español:

1. Quién soy — recordatorio breve de identidad y rol
2. Dónde quedamos — resumen de lo trabajado en esta sesión
3. Conceptos nuevos — ideas o términos que emergieron
4. Decisiones tomadas — resoluciones concretas adoptadas
5. Tensiones abiertas — preguntas sin resolver o conflictos pendientes
6. Próximo paso — una acción concreta para la siguiente sesión

Usa formato Markdown. Sé preciso y denso, no redundante."

    CIERRE_MSGS=$(jq -n \
        --arg sp "$CIERRE_PROMPT" \
        --argjson h "$HISTORY_DATA" \
        '[{role:"system", content:$sp}] + $h + [{role:"user", content:"Genera el documento de cierre de esta sesión."}]')

    BODY=$(llamar_api "$CIERRE_MSGS" "$MODEL" "$TEMP")
    [[ $? -ne 0 ]] && exit 1

    AI_TEXT=$(echo "$BODY" | jq -r '.choices[0].message.content')

    FECHA=$(date +%Y-%m-%d)
    HORA=$(date +%H:%M)
    OUTFILE="$VAULT_SOMA/02_Conciencia/sesiones/${FECHA}_cierre_sesion.md"

    CONTENIDO="---
fecha: $FECHA
hora: $HORA
tipo: cierre_sesion
generado_con: SOMA-Groq-$MODEL
---

$AI_TEXT

[[MOC_SOMA]]"

    echo ""
    echo "$AI_TEXT"
    echo ""

    guardar_en_vault "$OUTFILE" "$CONTENIDO" "cierre de sesión"
    exit 0
fi

# =============================================================================
# --resumir: resume historial sin cerrarlo
# =============================================================================

if [[ "$RESUMIR" == true ]]; then
    echo "[SOMA] Resumiendo sesión actual..."

    HISTORY_DATA=$(cat "$HISTORY")
    HISTORY_LEN=$(echo "$HISTORY_DATA" | jq 'length')

    if [[ "$HISTORY_LEN" -eq 0 ]]; then
        echo "[SOMA] No hay historial activo para resumir."
        exit 0
    fi

    RESUMIR_PROMPT="Eres SOMA. Resume en 5 puntos concisos lo trabajado en esta sesión hasta ahora. Sin secciones, sin encabezados. Solo los puntos más importantes en español."

    RESUMIR_MSGS=$(jq -n \
        --arg sp "$RESUMIR_PROMPT" \
        --argjson h "$HISTORY_DATA" \
        '[{role:"system", content:$sp}] + $h + [{role:"user", content:"Resume la sesión actual."}]')

    BODY=$(llamar_api "$RESUMIR_MSGS" "$MODEL" "$TEMP")
    [[ $? -ne 0 ]] && exit 1

    AI_TEXT=$(echo "$BODY" | jq -r '.choices[0].message.content')
    echo ""
    echo "[SOMA]: $AI_TEXT"
    echo ""
    exit 0
fi

# =============================================================================
# --web: búsqueda web via compound-beta
# =============================================================================

if [[ -n "$WEB_QUERY" ]]; then
    echo "[SOMA] Buscando en la web: '$WEB_QUERY'..."

    WEB_MSGS=$(jq -nc --arg q "$WEB_QUERY" '[{role:"user", content:$q}]')

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(jq -nc --arg q "$WEB_QUERY" \
            '{model:"compound-beta", messages:[{role:"user",content:$q}]}')")

    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_STATUS" -ne 200 ]]; then
        echo "[SOMA] compound-beta no disponible, usando modelo estándar..." >&2
        BODY=$(llamar_api "$WEB_MSGS" "$MODEL" "$TEMP")
        [[ $? -ne 0 ]] && exit 1
    fi

    AI_TEXT=$(echo "$BODY" | jq -r '.choices[0].message.content')
    echo ""
    echo "[SOMA]: $AI_TEXT"
    echo ""

    # Búsquedas web no saturan historial — solo referencia corta
    RESUMEN_WEB=$(echo "$AI_TEXT" | head -c 300)
    actualizar_historial "[web: $WEB_QUERY]" "$RESUMEN_WEB"

    if [[ "$SAVE" == true ]]; then
        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        FECHA=$(date +%Y-%m-%d)
        HORA=$(date +%H:%M)
        OUTFILE="$VAULT_SOMA/05_Salida/soma_web_${TIMESTAMP}.md"
        CONTENIDO="---
fecha: $FECHA
hora: $HORA
tipo: busqueda_web
generado_con: SOMA-Groq-compound-beta
---

# Búsqueda SOMA — $FECHA $HORA

**Consulta:** $WEB_QUERY

**Respuesta:**

$AI_TEXT

[[MOC_SOMA]]"
        guardar_en_vault "$OUTFILE" "$CONTENIDO" "búsqueda web"
    fi
    exit 0
fi

# =============================================================================
# RECOLECCIÓN DE CHUNK EXTERNO
# =============================================================================

USER_INPUT=""
CHUNK_EXTERNO=""

# --extraer: extrae contenido de URL
if [[ -n "$EXTRAER_URL" ]]; then
    echo "[SOMA] Extrayendo contenido de: $EXTRAER_URL"
    RAW_TEXT=$(curl -s -A "Mozilla/5.0" "$EXTRAER_URL" | lynx -dump -stdin 2>/dev/null | head -c 8000)
    if [[ -z "$RAW_TEXT" ]]; then
        echo "[SOMA] Error: no se pudo extraer contenido de $EXTRAER_URL"
        exit 1
    fi
    CHUNK_EXTERNO="$RAW_TEXT"
    INPUT_ORIGINAL="--extraer $EXTRAER_URL"
fi

# --unir: uno o varios archivos como contexto
if [[ ${#ARCHIVOS_UNIR[@]} -gt 0 ]]; then
    for archivo in "${ARCHIVOS_UNIR[@]}"; do
        if [[ ! -f "$archivo" ]]; then
            echo "[SOMA] Error: archivo no encontrado: $archivo"
            exit 1
        fi
        contenido_archivo=$(head -c 12000 "$archivo")
        CHUNK_EXTERNO+="
--- ARCHIVO: $(basename "$archivo") ---
$contenido_archivo
"
        echo "[SOMA] Archivo cargado: $(basename "$archivo") ($(wc -c < "$archivo") bytes)" >&2
    done
    INPUT_ORIGINAL="--unir ${ARCHIVOS_UNIR[*]}"
fi

# --conectar: inyecta desde pipe
if [[ "$CONECTAR" == true ]]; then
    if [[ -t 0 ]]; then
        echo "[SOMA] Error: --conectar requiere datos por pipe. Ejemplo: cat archivo | soma --con 'consulta'"
        exit 1
    fi
    CHUNK_EXTERNO=$(head -c 12000)
    echo "[SOMA] Contenido recibido desde pipe." >&2
    INPUT_ORIGINAL="--conectar"
fi

# =============================================================================
# --buscar: escaneo del vault (RAG)
# =============================================================================

VAULT_CONTEXT=""
if [[ -n "$BUSCAR_TERM" ]]; then
    if [[ -n "$BUSCAR_PATH" ]]; then
        SEARCH_PATHS=("$BUSCAR_PATH")
        echo "[SOMA] Escaneando '$BUSCAR_TERM' en: $BUSCAR_PATH"
    else
        SEARCH_PATHS=("$VAULT_SOMA" "$VAULT_ZAF")
        echo "[SOMA] Escaneando '$BUSCAR_TERM' en vault completo..."
    fi

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        CONTENT=$(head -c 2000 "$f")
        LINK_ALERTS=""
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            found=false
            for sp in "${SEARCH_PATHS[@]}"; do
                [[ -f "$sp/$link.md" ]] && found=true && break
            done
            [[ "$found" == false ]] && LINK_ALERTS+=" (ALERTA: link roto '$link')"
        done < <(echo "$CONTENT" | grep -oE "\[\[[^]]+\]\]" | sed 's/[][]//g')
        VAULT_CONTEXT+="
--- DOCUMENTO: $(basename "$f")$LINK_ALERTS ---
$CONTENT
"
    done < <(grep -rli "$BUSCAR_TERM" "${SEARCH_PATHS[@]}" 2>/dev/null | grep "\.md$" | head -n 5)

    [[ -z "$VAULT_CONTEXT" ]] && echo "[SOMA] Sin resultados para '$BUSCAR_TERM'."
fi

# =============================================================================
# CONSTRUCCIÓN DEL MENSAJE FINAL
# =============================================================================

[[ -z "$USER_INPUT" ]] && USER_INPUT="$QUERY_LIBRE"

# Combinar chunk externo con instrucción del usuario
if [[ -n "$CHUNK_EXTERNO" ]]; then
    if [[ -n "$USER_INPUT" ]]; then
        USER_INPUT="INSTRUCCIÓN: $USER_INPUT

TEXTO DE REFERENCIA:
$CHUNK_EXTERNO"
    else
        if [[ -n "$EXTRAER_URL" ]]; then
            USER_INPUT="Extrae del siguiente texto: TÍTULO, BAJADA y CUERPO del artículo. Si alguno no existe, indícalo.

Texto:
$CHUNK_EXTERNO"
        else
            USER_INPUT="Recibiste el siguiente contenido. Espera instrucciones o analízalo brevemente:

$CHUNK_EXTERNO"
        fi
    fi
fi

# --registrar: la instrucción incluye la ruta destino
if [[ -n "$REGISTRAR_RUTA" ]]; then
    if [[ -z "$USER_INPUT" ]]; then
        echo "[SOMA] Error: --registrar requiere una consulta. Ejemplo: soma --reg ruta.md 'genera el contenido'"
        exit 1
    fi
    USER_INPUT="$USER_INPUT

INSTRUCCIÓN ESPECIAL: Tu respuesta será guardada como archivo Markdown en: $REGISTRAR_RUTA
Genera únicamente el contenido del archivo, sin explicaciones adicionales."
fi

if [[ -z "$USER_INPUT" ]]; then
    echo "[SOMA] Escribe tu consulta. Ejemplo: soma 'qué pendientes tengo'"
    echo "       Usa --ayuda para ver todas las opciones."
    exit 1
fi

# Inyectar contexto de vault
[[ -n "$VAULT_CONTEXT" ]] && USER_INPUT="CONTEXTO DEL VAULT:
$VAULT_CONTEXT

CONSULTA: $USER_INPUT"

# Construir array de mensajes
PROYECTO_MSG=""
if [[ -n "$PROYECTO_ACTIVO" ]]; then
    PROYECTO_MSG=$(jq -nc --arg p "PROYECTO ACTIVO: $PROYECTO_ACTIVO" '{role:"system", content:$p}')
fi

# --recordar: inyecta el último cierre de sesión como contexto de mediano plazo (Capa 2)
RECORDAR_MSG=""
if [[ "$RECORDAR" == true ]]; then
    ULTIMO_CIERRE=$(find "$VAULT_SOMA/02_Conciencia/sesiones" -name "*_cierre_sesion.md" | sort | tail -n 1)
    if [[ -n "$ULTIMO_CIERRE" ]]; then
        CIERRE_CONTENT=$(head -c 4000 "$ULTIMO_CIERRE")
        RECORDAR_MSG=$(jq -nc --arg c "MEMORIA DE SESIÓN ANTERIOR ($(basename "$ULTIMO_CIERRE")):
$CIERRE_CONTENT" '{role:"system", content:$c}')
        echo "[SOMA] Contexto cargado: $(basename "$ULTIMO_CIERRE")" >&2
    else
        echo "[SOMA] No se encontró ningún cierre de sesión previo." >&2
    fi
fi

SYSTEM_MSG=$(jq -nc --arg c "$SYSTEM_PROMPT" '{role:"system", content:$c}')
USER_INFO_MSG=$(jq -nc --arg c "CONTEXTO DEL USUARIO: $USER_DATA" '{role:"system", content:$c}')
USER_MSG=$(jq -nc --arg c "$USER_INPUT" '{role:"user", content:$c}')
HISTORY_DATA=$(cat "$HISTORY")

if [[ -n "$PROYECTO_ACTIVO" && -n "$RECORDAR_MSG" ]]; then
    FULL_MESSAGES=$(jq -n \
        --argjson s "$SYSTEM_MSG" \
        --argjson i "$USER_INFO_MSG" \
        --argjson p "$PROYECTO_MSG" \
        --argjson r "$RECORDAR_MSG" \
        --argjson h "$HISTORY_DATA" \
        --argjson u "$USER_MSG" \
        '[$s, $i, $p, $r] + $h + [$u]')
elif [[ -n "$PROYECTO_ACTIVO" ]]; then
    FULL_MESSAGES=$(jq -n \
        --argjson s "$SYSTEM_MSG" \
        --argjson i "$USER_INFO_MSG" \
        --argjson p "$PROYECTO_MSG" \
        --argjson h "$HISTORY_DATA" \
        --argjson u "$USER_MSG" \
        '[$s, $i, $p] + $h + [$u]')
elif [[ -n "$RECORDAR_MSG" ]]; then
    FULL_MESSAGES=$(jq -n \
        --argjson s "$SYSTEM_MSG" \
        --argjson i "$USER_INFO_MSG" \
        --argjson r "$RECORDAR_MSG" \
        --argjson h "$HISTORY_DATA" \
        --argjson u "$USER_MSG" \
        '[$s, $i, $r] + $h + [$u]')
else
    FULL_MESSAGES=$(jq -n \
        --argjson s "$SYSTEM_MSG" \
        --argjson i "$USER_INFO_MSG" \
        --argjson h "$HISTORY_DATA" \
        --argjson u "$USER_MSG" \
        '[$s, $i] + $h + [$u]')
fi

BODY=$(llamar_api "$FULL_MESSAGES" "$MODEL" "$TEMP")
[[ $? -ne 0 ]] && exit 1

# =============================================================================
# SALIDA
# =============================================================================

AI_TEXT=$(echo "$BODY" | jq -r '.choices[0].message.content')

# =============================================================================
# SINAPSIS SUPERVISADA — detección de links propuestos
# =============================================================================

SINAPSIS=$(echo "$AI_TEXT" | grep -oE "\[\[[^]]+\]\]" | sed 's/[][]//g' | sort -u)

if [[ -n "$SINAPSIS" ]]; then
    echo ""
    echo "[SOMA] Links propuestos en la respuesta:"
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        # Buscar el documento en el vault
        DOC_PATH=$(find "$VAULT_SOMA" -name "${link}.md" 2>/dev/null | head -n1)
        if [[ -z "$DOC_PATH" ]]; then
            echo "       ⚠️  [[${link}]] — documento no encontrado en vault"
        else
            echo -n "       ¿Aprobar sinapsis [[${link}]]? [S/n]: "
            read -r aprueba < /dev/tty
            if [[ -z "$aprueba" || "$aprueba" =~ ^[sS]$ ]]; then
                echo "[SOMA] Sinapsis aprobada: [[${link}]]"
                # Registrar en log de sinapsis
                echo "$(date +%Y-%m-%d_%H:%M) | APROBADA | [[${link}]] | $DOC_PATH" \
                    >> "$VAULT_SOMA/02_Conciencia/sesiones/sinapsis_log.txt"
            else
                echo "[SOMA] Sinapsis rechazada: [[${link}]]"
                echo "$(date +%Y-%m-%d_%H:%M) | RECHAZADA | [[${link}]] | $DOC_PATH" \
                    >> "$VAULT_SOMA/02_Conciencia/sesiones/sinapsis_log.txt"
            fi
        fi
    done <<< "$SINAPSIS"
fi

echo ""
echo "[SOMA]: $AI_TEXT"
echo ""

# --guardar: guarda en 05_Salida con timestamp
if [[ "$SAVE" == true ]]; then
    TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
    FECHA=$(date +%Y-%m-%d)
    HORA=$(date +%H:%M)
    OUTFILE="$VAULT_SOMA/05_Salida/soma_${TIMESTAMP}.md"
    CONTENIDO="---
fecha: $FECHA
hora: $HORA
tipo: respuesta_soma
generado_con: SOMA-Groq-$MODEL
proyecto: ${PROYECTO_ACTIVO:-ninguno}
---

# Respuesta SOMA — $FECHA $HORA

**Consulta:** $INPUT_ORIGINAL

**Respuesta:**

$AI_TEXT

[[MOC_SOMA]]"
    guardar_en_vault "$OUTFILE" "$CONTENIDO" "respuesta"
fi

# --registrar: escribe en ruta específica del vault
if [[ -n "$REGISTRAR_RUTA" ]]; then
    # Resolver ruta: si es relativa, anclar al vault SOMA
    if [[ "$REGISTRAR_RUTA" != /* ]]; then
        RUTA_ABSOLUTA="$VAULT_SOMA/$REGISTRAR_RUTA"
    else
        RUTA_ABSOLUTA="$REGISTRAR_RUTA"
    fi

    FECHA=$(date +%Y-%m-%d)
    HORA=$(date +%H:%M)

    # Preservar frontmatter existente si el archivo ya existe
    if [[ -f "$RUTA_ABSOLUTA" ]]; then
        FRONTMATTER=$(awk '/^---/{f=!f; if(!f) exit} f' "$RUTA_ABSOLUTA")
        CONTENIDO_REG="---
$FRONTMATTER
fecha_actualizacion: $FECHA
generado_con: SOMA-Groq-$MODEL
---

$AI_TEXT"
    else
        CONTENIDO_REG="---
fecha: $FECHA
hora: $HORA
generado_con: SOMA-Groq-$MODEL
---

$AI_TEXT"
    fi

    guardar_en_vault "$RUTA_ABSOLUTA" "$CONTENIDO_REG" "$(basename "$REGISTRAR_RUTA")"
fi

# Actualizar historial
actualizar_historial "$INPUT_ORIGINAL" "$AI_TEXT"
