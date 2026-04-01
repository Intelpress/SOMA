# SOMA: Active Memory Orientation System in Natural Language for Constrained Hardware

**Juan José Arellano**
Educator, Independent Researcher — Quintero, Chile
intelpress.4.0@gmail.com
March 2026

---

## Abstract

SOMA (Active Memory Orientation System) is a personal agent that operates entirely on local Markdown files, designed to run on modest hardware (a ThinkPad T460 with 8 GB of RAM, no GPU) using core-utils utilities (bash, curl, jq, lynx) and publicly accessible APIs. Its architecture separates the engine (soma.sh) from the behavior harness (soma.json), allowing the agent's personality and rules to be modified without touching any code. SOMA implements three layers of temporary memory—current session, session closings (cross-session continuity), and, in the future, semantic search—and guarantees that no write to the knowledge base occurs without explicit user confirmation (Supervised Synapse protocol). This article describes the design decisions, architecture, and results of the defined evaluation protocol, providing a verifiable foundation for building sovereign personal agents with minimal resources.

---

## 1. Introduction

We live in an era where AI assistants promise to manage our personal information, but almost always demand expensive hardware, permanent cloud connectivity, or monthly subscriptions. For those who research or produce knowledge from peripheral economies, without institutional infrastructure or budget for specialized hardware, these tools remain out of reach—deepening a digital divide that undermines research and development for actors in the Global South, and the discovery of talent for the Global North.

Current artificial intelligence tools typically require costly hardware, constant cloud connectivity, or subscriptions, placing them beyond the reach of those who work with modest equipment, value their privacy, and lack the economic resources to meet these requirements. The same is true of the construction of massive, expensive data centers, which significantly strain water and energy resources, affecting the communities and territories where they are installed.

On the other hand, personal knowledge management (PKM) tools like Obsidian were born as plain-text databases based on the Zettelkasten method. Their primary function was to store and connect notes by creating manual links between them (bidirectionality) and to visualize the contents of a folder by displaying knowledge graphs so that the user—not the machine—could find the connections. Today, it is possible to turn Obsidian into an "active second brain" with reasoning capabilities through third-party extensions, or by building your own personal agent in a local and sovereign manner.

SOMA was created to occupy that space. It is a personal agent that:

- Runs on a nearly decade-old laptop (no GPU).
- Stores all knowledge in local Markdown, under the user's control.
- Uses free, auditable tools.
- Implements Supervised Synapse: the user controls what information the agent receives and what is written to the vault.

**What does "in natural language" mean?**

In SOMA, both the interaction with the user and the definition of agent behavior are carried out through plain text. No complex commands or code are needed: the user writes phrases like "Remember that the key is in the configuration file" or "What documents talk about the SOMA project?", and the agent responds in Spanish. Furthermore, the agent's personality and rules are written in a JSON file in natural language (the harness), which allows its behavior to be modified without touching the engine.

---

## 2. Hardware and Technology Stack

- **Hardware:** Lenovo ThinkPad T460, Intel Core i5-6200U, 8 GB RAM, 234 GB hard drive. No GPU.
- **Operating system:** MX-Linux 26.3 "Libretto" (non-systemd).
- **Tools:** bash, curl, jq, lynx, grep (all available in standard repositories).
- **Inference:** Groq API (llama-3.3-70b-versatile). Fallback via OpenRouter: meta-llama/llama-3.3-70b-instruct:free → qwen/qwen3-235b-a22b:free → deepseek/deepseek-chat-v3-0324:free.

---

## 3. Architecture

SOMA consists of three clearly differentiated elements:

**The engine (soma.sh):** a bash script (approximately 760 lines in version 0.4.1) that processes commands, communicates with APIs, manages conversation history, and applies the confirmation protocol.

**The harness (soma.json):** a JSON file containing the system prompt, agent identity, behavior rules (including the Supervised Synapse), and model configuration.

**The knowledge base (~/vault/SOMA/):** a folder and Markdown file structure that acts as external memory, organized into: 00_Entrada, 01_Caracter, 02_Conciencia, 03_Proyectos, 04_Sueños, 05_Salida, and 06_Archivo.

This separation follows the philosophy of Pan et al. (2026): the engine executes, the harness defines, the knowledge base persists.

Each API query assembles a message in the following order:

```
[system_prompt] + [user_context] + [project?] + [session_memory?] + [history] + [user_message]
```

The history is limited to the last 10 turns to prevent degradation from context rot [1].

### 3.1 Main Commands

| Flag | Alias | Function |
|------|-------|----------|
| --web | --web | Natural language web search (Groq compound-beta) |
| --extraer URL | --ext | Extracts content from a URL |
| --buscar TERM | --bus | Scans the vault for a term |
| --conectar | --con | Injects text from pipe (stdin) |
| --unir FILE... | --uni | Injects one or more files as context |
| --guardar | --gua | Saves response to 05_Salida/ |
| --registrar PATH | --reg | Writes a supervised file to a specific path |
| --cerrar | --cer | Generates a session closing document |
| --reiniciar | --rei | Clears conversation history |
| --resumir | --res | Summarizes current history without closing it |
| --recordar | --rec | Loads the last session closing as context |
| --modo PROFILE | --mod | Switches active profile |
| --proyecto NAME | --pro | Injects project context |
| --ayuda | --ayu | Displays this help |

### 3.2 Operation Flow

When the user runs SOMA with a query and its corresponding flags, the engine (soma.sh) automatically loads two files: the harness (soma.json), which defines the agent's identity and rules, and the conversation history (soma_history.json), which contains the last 10 turns. If the user has included context flags (--buscar, --unir, --conectar, --recordar), the engine also accesses the vault and extracts the requested information. With all that material assembled, it builds the message and sends it to the API.

The API returns a response that the agent presents to the user. If that response includes links to vault documents ([[document_name]]), the Supervised Synapse is triggered: the agent implicitly asks *Approve synapse [[document_name]]? [Y/n]* and waits for confirmation. If the user approves, the proposed connection is recorded in 02_Conciencia/sesiones/sinapsis_log.txt. If rejected, it is discarded. In either case, the cycle may continue with a new query.

---

## 4. Three-Layer Temporary Memory

SOMA organizes its memory into four types, following a structure similar to what Google describes for Gemini (Chavan, 2026), though with fundamental differences in user control:

**Short-term layer:** history of the current session (last 10 turns). Stored in soma_history.json and cleared with --reiniciar. Equivalent to Gemini's *Raw data* concept: ephemeral working memory, active only during the session.

**Medium-term layer:** session closings. When --cerrar is executed, SOMA generates a structured document that includes a summary, new concepts, decisions made, open tensions, and the next step. In the following session, --recordar injects it as context, achieving continuity without reprocessing the entire history. Equivalent to Gemini's *user_context*, with a critical difference: in Gemini, that summary is generated by the system automatically and opaquely; in SOMA, it is generated by the agent under the user's explicit supervision.

**Long-term layer (designed, not yet implemented):** semantic search via embeddings. The plan is to use a vector index (R + SQLite) and a free endpoint. In the meantime, --buscar uses grep for exact-word search. Equivalent to *Semantic Memory* in Google Research terminology.

**Procedural memory:** the agent's rules, identity, and behavior are defined in soma.json. The agent "knows how to behave" without the user having to instruct it at every session. Equivalent to Google Research's *Procedural Memory*.

The following table summarizes the equivalences:

| Google Concept | SOMA Equivalent | Implementation |
|----------------|-----------------|----------------|
| Raw data / Session | Short-term layer | soma_history.json (last 10 turns) |
| user_context | Medium-term layer | Session closings (--cerrar / --recordar) |
| Semantic Memory | Long-term layer | Embeddings (designed, not implemented — currently grep) |
| Procedural Memory | Behavior harness | soma.json (rules, identity, behavior) |
| Memory Bank | Vault | ~/vault/SOMA/ (persistent cross-session storage) |

The most important difference from Gemini is not technical but a matter of design: in SOMA, no memory layer is built without explicit user intervention. The vault does not write itself. Session closings are generated when the user requests them and saved only if the user approves them. That difference is the Supervised Synapse.

---

## 5. Supervised Synapse

Supervised Synapse is the central design principle of SOMA: no connection between the agent and the knowledge base occurs without explicit user intervention. It is expressed in two moments:

**Context loading:** the user decides what information the agent receives before each query, through explicit flags. The agent does not access the vault on its own initiative.

**Writing to the vault:** when the agent's response includes connections to vault documents ([[document_name]]), the confirmation protocol is triggered. The script displays:

```
Approve synapse [[document_name]]? [Y/n]:
```

If the user approves, the proposed connection is recorded in 02_Conciencia/sesiones/sinapsis_log.txt. If rejected, it is discarded. In either case, the cycle may continue with a new query.

This mechanism makes the user the ultimate guardian of their knowledge. It is not about trusting the agent, but about making trust irrelevant to the vault's integrity. The agent proposes, the user decides.

Supervised Synapse is not a security patch tacked on at the end of the design. It is a fundamental architectural decision: personal knowledge is constituted in the human-agent interaction; it is not a product that the agent generates on its own.

---

## 6. Discussion

### 6.1 SOMA as a Minimal Implementation of the NLAH Paradigm

The work of Pan et al. (2026) demonstrated the viability of natural-language harnesses with state-of-the-art cloud models. SOMA takes the same idea to the opposite extreme: a nearly decade-old laptop, command-line tools, and free APIs. The key decisions—bash as the engine, grep for retrieval, a 10-turn limit, session closings as cross-session memory—are not temporary concessions waiting to be replaced; they are deliberate design choices that prioritize auditability, portability, and minimal resource consumption.

### 6.2 What Does Individual Sovereignty Mean?

We define individual sovereignty over the agent as:

- Data resides on hardware the user owns.
- All code is free and can be audited.
- There is no vendor lock-in at the data layer — the vault is plain Markdown.
- Zero economic cost.

SOMA meets all four criteria. However, sovereignty is partial as long as inference is performed on third-party servers. Although data is not stored persistently under Groq's current terms, every query leaves the user's machine. The design does not prevent using a local model in the future — in fact, it is built with that in mind. We declare this limitation honestly.

### 6.3 SOMA and Gemini: The Difference That Matters

Gemini and SOMA implement comparable memory structures. But while Gemini builds the user's profile automatically and opaquely — the system decides what to remember, when, and how — SOMA inverts that relationship: the user decides what enters the vault, what gets connected, and what is discarded. This is not a difference of scale or technical capability. It is a difference of philosophy: who controls the knowledge.

### 6.4 Current Limitations

- **Semantic search layer not implemented:** exact-word search is insufficient for conceptual queries.
- **Formal evaluation pending:** claims about utility and performance are currently qualitative and preliminary.
- **Dependency on free APIs:** usage limits may change and free models may be discontinued.
- **Language:** the vault and test queries are in Spanish. Reproducing the system in other languages requires adjusting the prompts.
- **Hallucination without context:** when SOMA does not receive an explicit vault listing, it may propose connections to non-existent documents. The Supervised Synapse mitigates the consequences, but does not eliminate the problem at its source.

---

## 7. Conclusions

SOMA demonstrates that it is possible to build a personal agent with persistent memory, defined identity, and explicit user control over knowledge, running on nearly decade-old hardware, with standard Linux tools and zero cost. It implements the natural-language harness paradigm (Pan et al., 2026) at the most modest end of the resource spectrum.

The central contribution of this work is the Supervised Synapse protocol: an architectural guarantee that no modification to the knowledge base occurs without explicit user confirmation, expressed in two moments — context loading and writing to the vault. It is not a security mechanism added as an afterthought; it is a design decision that defines the relationship between the agent and its user.

SOMA does not compete with large AI systems in inference capacity or scale. It competes on different ground: transparency, auditability, and individual sovereignty. For those who research or produce knowledge from peripheral economies, without institutional infrastructure or budget for specialized hardware, SOMA offers a concrete and honest foundation for building.

The project is in active development. This article is open documentation for anyone who wishes to explore, critique, or adapt these ideas.

---

## 8. Acknowledgments

Developed in conversation with Claude Sonnet 4.6 (Anthropic) as a development companion. The intellectual authorship and all design decisions belong to the author.

---

## 9. References

[1] Hong, K., Troynikov, A., & Huber, J. (2025). Context Rot: How Increasing Input Tokens Impacts LLM Performance. Chroma Research. https://research.trychroma.com/context-rot

[2] Pan, L., Zou, L., Guo, S., Ni, J., & Zheng, H.-T. (2026). Natural-Language Agent Harnesses. arXiv:2603.25723.

[3] Lewis, P., et al. (2021). Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks. arXiv:2005.11401.

[4] Zhang, H., et al. (2026). MemSkill: Learning and Evolving Memory Skills for Self-Evolving Agents. arXiv:2602.02474.

[5] Sun, Q., et al. (2025). Docs2KG: Unified Knowledge Graph Construction from Heterogeneous Documents. ACM WWW 2025. https://dl.acm.org/doi/10.1145/3701716.3715309

[6] Harvard Business Review Analytic Services. (2025). AI Agent Trust Report. Fortune, Dec 9, 2025. https://fortune.com/2025/12/09/harvard-business-review-survey-only-6-percent-companies-trust-ai-agents/

[7] ITBrief. (2025). Survey finds slow adoption of autonomous AI agents in enterprises. https://itbrief.news/story/survey-finds-slow-adoption-of-autonomous-ai-agents-in-enterprises

[8] Ahrens, S. (2022). How to Take Smart Notes (2nd ed.). Sönke Ahrens.

[9] Chavan, R. (2026). Inside Gemini's Memory: Context, User Profiles, and Personalization. Medium, February 2026. https://medium.com/@rushikeshchavan_99600/inside-geminis-memory-context-user-profiles-and-personalization-87bc1ae4ba18


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
