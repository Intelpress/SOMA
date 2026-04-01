# SOMA: Sistema de Orientación de Memoria Activa en Lenguaje Natural para Hardware Restringido

**Juan José Arellano**  
Educador, Investigador independiente — Quintero, Chile  
intelpress.4.0@gmail.com  
Marzo 2026

---

## Resumen

SOMA (Sistema de Orientación de Memoria Activa) es un agente personal que opera completamente sobre archivos Markdown locales, diseñado para funcionar en hardware modesto (un ThinkPad T460 con 8 GB de RAM, sin GPU) mediante utilidades de core-utils (bash, curl, jq, lynx) y APIs de acceso público. Su arquitectura separa el motor (`soma.sh`) del arnés de comportamiento (`soma.json`), permitiendo modificar la personalidad y reglas del agente sin tocar código. SOMA implementa tres capas de memoria temporal —sesión actual, cierres de sesión (continuidad entre sesiones) y, en el futuro, búsqueda semántica— y garantiza que ninguna escritura en la base de conocimiento ocurra sin confirmación explícita del usuario (protocolo de *Sinapsis Supervisada*). Este artículo describe las decisiones de diseño, la arquitectura y los resultados del protocolo de evaluación definido, ofreciendo una base verificable para construir agentes personales soberanos con recursos mínimos.

---

## 1. Introducción

Vivimos en una época donde los asistentes de IA prometen gestionar nuestra información personal, pero casi siempre exigen hardware caro, conexión permanente a la nube o suscripciones mensuales. Para quienes investigan o producen conocimiento desde economías periféricas, sin infraestructura institucional ni presupuesto para hardware especializado, estas herramientas quedan fuera de alcance, y profundizando una brecha digital que compromete la investigación y el desarrollo para los actores del Sur Global, y el descubrimiento de talentos para el Norte Global.

Las herramientas de inteligencia artificial actuales suelen requerir hardware costoso, conexión constante a la nube o suscripciones, quedando fuera del alcance de quienes ;trabajan con equipos modestos, valoran su privacidad y no cuentan con los recursos económicos para estos efectos. Así como la construcción de gigantescos y costosos data centers, que afectan considerablemente los recursos hídricos y energéticos, afectando a las comunidades y territorios donde son instalados.

Por otro lado, herramientas de gestión del conocimiento personal (PKM) [Obsidian](https://publish.obsidian.md/intuiciones-comunicativas/Intuiciones/AUTONOM%C3%8DA/Herramientas+autonom%C3%ADa/Gesti%C3%B3n+personal+del+conocimiento+-+PKM)nacieron como bases de datos de texto plano basadas en el método **Zettelkasten**. Su función principal era almacenar y conectar notas creando enlaces manuales entre notas (bi-direccionalidad) y visualizar el contenido de un carpeta mostrando gráficos de conocimiento para que el usuario, y no la máquina, encontrara las conexiones. Hoy en día, es posible convertir a Obsidian  en un "segundo cerebro activo" con capacidad de razonamiento mediante extensiones de terceros, o bien creando tu propio agente personal de manera local y soberana.

SOMA nace para ocupar ese espacio. Es un agente personal que:

- Funciona en un portátil de hace casi una década (sin GPU).
- Almacena todo el conocimiento en Markdown local, bajo control del usuario.
- Utiliza herramientas libres y auditables.
- Implementa Sinapsis Supervisada: el usuario controla qué información recibe el  agente y qué se escribe en el vault.


**¿Qué significa “en lenguaje natural”?** 

En SOMA, tanto la interacción con el usuario como la definición del comportamiento del agente se realizan mediante texto común. No se necesitan comandos complejos ni código: el usuario escribe frases como *“Recuerda que la clave está en el archivo de configuración”* o *“¿Qué documentos hablan sobre el proyecto SOMA?”*, y el agente responde en español. Además, la personalidad y las reglas del agente están escritas en un archivo JSON en lenguaje natural (el *arnés*), lo que permite modificar su comportamiento sin tocar el motor.

---
## 2. Hardware y herramientas tecnológicas (Stack)

- **Hardware:** Lenovo ThinkPad T460, Intel Core i5-6200U, 8 GB RAM, disco duro 234 GB. Sin GPU.
- **Sistema operativo:** MX-Linux 26.3 "Libretto" (sin systemd).
- **Herramientas:** `bash`, `curl`, `jq`, `lynx`, `grep` (todas en repositorios estándar).
- **Inferencia:** API de Groq (`llama-3.3-70b-versatile`). Fallback con OpenRouter: `meta-llama/llama-3.3-70b-instruct:free` → `qwen/qwen3-235b-a22b:free` → `deepseek/deepseek-chat-v3-0324:free`.

---

## 3. Arquitectura

SOMA se compone de tres elementos bien diferenciados:

1. **El motor (`soma.sh`):** un script en bash (unas 760 líneas en su versión 0.4.1) que procesa los comandos, se comunica con las APIs, gestiona el historial y aplica el protocolo de confirmación.
2. **El arnés (`soma.json`):** un archivo JSON que contiene el _prompt_ del sistema, la identidad del agente, las reglas de comportamiento (incluyendo la Sinapsis Supervisada) y la configuración de los modelos.
3. **La base de conocimiento (`~/vault/SOMA/`):** una estructura de carpetas y archivos Markdown que actúa como memoria externa, organizada en: `00_Entrada`, `01_Caracter`, `02_Conciencia`, `03_Proyectos`, `04_Sueños`, `05_Salida` y `06_Archivo`.

Esta separación sigue la filosofía de Pan et al. (2026): el motor ejecuta, el arnés define, la base de conocimiento persiste.

Cada consulta a la API ensambla un mensaje con el siguiente orden:

```
[prompt_sistema] + [contexto_usuario] + [proyecto?] + [memoria_sesión?] + [historial] + [mensaje_usuario]
```

El historial se limita a los últimos 10 turnos para evitar la degradación por _context rot_ [1].

### 3.1 Comandos principales

|Flag|Alias|Función|
|---|---|---|
|`--web`|`--web`|Búsqueda web en lenguaje natural (Groq compound-beta)|
|`--extraer URL`|`--ext`|Extrae contenido de una URL|
|`--buscar TÉRMINO`|`--bus`|Escanea el vault por término|
|`--conectar`|`--con`|Inyecta texto desde pipe (stdin)|
|`--unir ARCHIVO...`|`--uni`|Inyecta uno o varios archivos como contexto|
|`--guardar`|`--gua`|Guarda respuesta en `05_Salida/`|
|`--registrar RUTA`|`--reg`|Escribe archivo supervisado en ruta específica|
|`--cerrar`|`--cer`|Genera documento de cierre de sesión|
|`--reiniciar`|`--rei`|Limpia historial de conversación|
|`--resumir`|`--res`|Resume historial actual sin cerrarlo|
|`--recordar`|`--rec`|Carga el último cierre de sesión como contexto|
|`--modo PERFIL`|`--mod`|Cambia perfil activo|
|`--proyecto NOMBRE`|`--pro`|Inyecta contexto de proyecto|
|`--ayuda`|`--ayu`|Muestra esta ayuda|

---

### 3.2 **Flujo de operación**

Cuando el usuario ejecuta SOMA con una consulta y sus flags correspondientes, el motor (`soma.sh`) carga automáticamente dos archivos: el arnés (`soma.json`), que define la identidad y las reglas del agente, y el historial de conversación (`soma_history.json`), que contiene los últimos 10 turnos. Si el usuario ha incluido flags de contexto (`--buscar`, `--unir`, `--conectar`, `--recordar`), el motor accede además al vault y extrae la información solicitada. Con todo ese material ensamblado, construye el mensaje y lo envía a la API.

La API devuelve una respuesta que el agente presenta al usuario. Si esa respuesta incluye enlaces a documentos del vault (`[[nombre_documento]]`), se activa la Sinapsis Supervisada: el agente pregunta implícitamente `¿Aprobar sinapsis [[nombre_documento]]? [S/n]` y espera confirmación. Si el usuario aprueba, la conexión propuesta queda registrada en`02_Conciencia/sesiones/sinapsis_log.txt`. Si rechaza, se descarta. En ambos casos el ciclo puede continuar con una nueva consulta.

---

## 4. Memoria temporal en tres capas

SOMA organiza su memoria en cuatro tipos, siguiendo una estructura similar a la que Google describe para Gemini (Chavan, 2026), aunque con diferencias fundamentales en el control del usuario:

- **Capa corto plazo:** historial de la sesión actual (últimos 10 turnos). Se almacena en `soma_history.json` y se limpia con `--reiniciar`. Equivale al concepto de _Raw data_ de Gemini: memoria de trabajo efímera, activa solo durante la sesión.
    
- **Capa mediano plazo:** cierres de sesión. Al ejecutar `--cerrar`, SOMA genera un documento estructurado que incluye resumen, conceptos nuevos, decisiones tomadas, tensiones abiertas y próximo paso. En la siguiente sesión, `--recordar` lo inyecta como contexto, logrando continuidad sin reprocesar todo el historial. Equivale al _user_context_ de Gemini, con una diferencia crítica: en Gemini ese resumen lo genera el sistema de forma automática y opaca; en SOMA lo genera el agente bajo supervisión explícita del usuario.
    
- **Capa largo plazo (diseñada, no implementada):** búsqueda semántica mediante embeddings. Se planea usar un índice vectorial (R + SQLite) y un endpoint gratuito. Mientras tanto, `--buscar` utiliza `grep` para búsqueda por palabras exactas. Equivale a la _Semantic Memory_ en la terminología de Google Research.
    
- **Memoria procedimental:** las reglas, la identidad y el comportamiento del agente están definidos en `soma.json`. El agente "sabe cómo comportarse" sin que el usuario lo instruya en cada sesión. Equivale a la _Procedural Memory_ de Google Research.
    

La tabla siguiente resume las equivalencias:

|Concepto Google|Equivalente en SOMA|Implementación|
|---|---|---|
|Raw data / Session|Capa corto plazo|`soma_history.json` (últimos 10 turnos)|
|user_context|Capa mediano plazo|Cierres de sesión (`--cerrar` / `--recordar`)|
|Semantic Memory|Capa largo plazo|Embeddings (diseñada, no implementada — actualmente `grep`)|
|Procedural Memory|Arnés de comportamiento|`soma.json` (reglas, identidad, comportamiento)|
|Memory Bank|Vault|`~/vault/SOMA/` (almacenamiento persistente entre sesiones)|

La diferencia más importante respecto a Gemini no es técnica sino de diseño: en SOMA, ninguna capa de memoria se construye sin intervención explícita del usuario. El vault no se escribe solo. Los cierres de sesión se generan cuando el usuario los solicita y se guardan solo si los aprueba. Esa diferencia es la Sinapsis Supervisada.

---

## 5. Sinapsis Supervisada

**Sinapsis Supervisada** es el principio de diseño central de SOMA: ninguna conexión entre el agente y la base de conocimiento ocurre sin intervención explícita del usuario. Se expresa en dos momentos:

1. **Carga de contexto:** el usuario decide qué información recibe el agente antes de cada consulta, mediante flags explícitos. El agente no accede al vault por iniciativa propia.
    
2. **Escritura en el vault:** cuando la respuesta del agente incluye conexiones a documentos del vault (`[[nombre_documento]]`), se activa el protocolo de confirmación. El script muestra:
    

```
¿Aprobar sinapsis [[nombre_documento]]? [S/n]:
```

Si el usuario aprueba, la conexión propuesta queda registrada en `02_Conciencia/sesiones/sinapsis_log.txt`. Si rechaza, se descarta. En ambos casos el ciclo puede continuar con una nueva consulta.

Este mecanismo convierte al usuario en el guardián definitivo de su conocimiento. No se trata de confiar en el agente, sino de hacer que la confianza sea irrelevante para la integridad del vault. El agente propone, el usuario dispone.

La Sinapsis Supervisada no es un parche de seguridad añadido al final del diseño. Es una decisión arquitectónica fundamental: el conocimiento personal se constituye en la interacción humano-agente, no es un producto que el agente genere por sí solo.

---

## 6. Discusión

### 6.1 SOMA como implementación mínima del paradigma NLAH

El trabajo de Pan et al. (2026) demostró la viabilidad de los arneses en lenguaje natural con modelos de última generación en la nube. SOMA lleva la misma idea al extremo opuesto: un portátil de hace casi una década, herramientas de línea de comandos y APIs gratuitas. Las decisiones clave —bash como motor, grep como recuperación, límite de 10 turnos, cierres como memoria entre sesiones— no son concesiones temporales que esperan ser reemplazadas; son opciones de diseño deliberadas que priorizan la auditabilidad, la portabilidad y el mínimo consumo de recursos.

### 6.2 ¿Qué significa soberanía individual?

Definimos soberanía individual sobre el agente como:

1. Los datos residen en hardware que el usuario posee.
2. Todo el código es libre y puede ser auditado.
3. No hay bloqueo de proveedor en la capa de datos — el vault es Markdown plano.
4. Coste económico cero.

SOMA cumple estos cuatro puntos. Sin embargo, la soberanía es parcial mientras la inferencia se realice en servidores de terceros. Aunque los datos no se almacenan de forma persistente según las condiciones actuales de Groq, cada consulta sale del equipo. El diseño no impide usar un modelo local en el futuro — de hecho, está pensado para ello. Declaramos este límite con honestidad.

### 6.3 SOMA y Gemini: la diferencia que importa

Gemini y SOMA implementan estructuras de memoria comparables. Pero mientras Gemini construye el perfil del usuario de forma automática y opaca — el sistema decide qué recordar, cuándo y cómo — SOMA invierte esa relación: el usuario decide qué entra al vault, qué se conecta y qué se descarta. No es una diferencia de escala ni de capacidad técnica. Es una diferencia de filosofía: quién tiene el control del conocimiento.

### 6.4 Limitaciones actuales

- **Capa de búsqueda semántica no implementada:** la búsqueda por palabras exactas es insuficiente para consultas conceptuales.
- **Evaluación formal pendiente:** las afirmaciones sobre utilidad y rendimiento son por ahora cualitativas y preliminares.
- **Dependencia de APIs gratuitas:** los límites de uso pueden cambiar y los modelos gratuitos pueden desaparecer.
- **Idioma:** el vault y las consultas de prueba están en español. Reproducir el sistema en otros idiomas requiere ajustar los prompts.
- **Alucinación sin contexto:** cuando SOMA no recibe un listado explícito del vault, puede proponer conexiones a documentos inexistentes. La Sinapsis Supervisada mitiga las consecuencias, pero no elimina el problema en origen.

---

## 7. Conclusiones

SOMA demuestra que es posible construir un agente personal con memoria persistente, identidad definida y control explícito del usuario sobre el conocimiento, funcionando en hardware de hace casi una década, con herramientas estándar de Linux y coste cero. Implementa el paradigma de arnés en lenguaje natural (Pan et al., 2026) en el extremo más modesto del espectro de recursos.

La contribución central de este trabajo es el protocolo de **Sinapsis Supervisada**: una garantía arquitectónica de que ninguna modificación del conocimiento ocurre sin confirmación explícita del usuario, expresada en dos momentos — la carga de contexto y la escritura en el vault. No es un mecanismo de seguridad añadido; es una decisión de diseño que define la relación entre el agente y su usuario.

SOMA no compite con los grandes sistemas de IA en capacidad de inferencia ni en escala. Compite en un terreno diferente: transparencia, auditabilidad y soberanía individual. Para quienes investigan o producen conocimiento desde economías periféricas, sin infraestructura institucional ni presupuesto para hardware especializado, SOMA ofrece una base concreta y honesta para construir.

El proyecto está en desarrollo activo. Este artículo es documentación abierta para quien quiera explorar, criticar o adaptar estas ideas.

---

## 8. Agradecimientos

Desarrollado en conversación con Claude Sonnet 4.6 (Anthropic) como compañero de desarrollo. La autoría intelectual y todas las decisiones de diseño son del autor.

---

## 9. Referencias

[1] Hong, K., Troynikov, A., & Huber, J. (2025). _Context Rot: How Increasing Input Tokens Impacts LLM Performance_. Chroma Research. https://research.trychroma.com/context-rot

[2] Pan, L., Zou, L., Guo, S., Ni, J., & Zheng, H.-T. (2026). _Natural-Language Agent Harnesses_. arXiv:2603.25723.

[3] Lewis, P., et al. (2021). _Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks_. arXiv:2005.11401.

[4] Zhang, H., et al. (2026). _MemSkill: Learning and Evolving Memory Skills for Self-Evolving Agents_. arXiv:2602.02474.

[5] Sun, Q., et al. (2025). _Docs2KG: Unified Knowledge Graph Construction from Heterogeneous Documents_. ACM WWW 2025. https://dl.acm.org/doi/10.1145/3701716.3715309

[6] Harvard Business Review Analytic Services. (2025). _AI Agent Trust Report_. Fortune, Dec 9, 2025. https://fortune.com/2025/12/09/harvard-business-review-survey-only-6-percent-companies-trust-ai-agents/

[7] ITBrief. (2025). _Survey finds slow adoption of autonomous AI agents in enterprises_. https://itbrief.news/story/survey-finds-slow-adoption-of-autonomous-ai-agents-in-enterprises

[8] Ahrens, S. (2022). _How to Take Smart Notes_ (2nd ed.). Sönke Ahrens.

[9] Chavan, R. (2026). _Inside Gemini's Memory: Context, User Profiles, and Personalization_. Medium, febrero 2026. https://medium.com/@rushikeshchavan_99600/inside-geminis-memory-context-user-profiles-and-personalization-87bc1ae4ba18

---
