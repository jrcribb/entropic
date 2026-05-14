# OpenClaw Core Runtime Container
# Hardened, non-root, read-only filesystem

FROM node:22-bookworm-slim

# Install runtime deps and create directories
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    pandoc \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    unzip \
    # Headless Chromium runtime dependencies (patchright)
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    fonts-liberation \
    fonts-noto-color-emoji \
    # Additional fonts for realistic browser fingerprint
    fonts-noto-core \
    fonts-dejavu-core \
    # Video codec libraries (h264 support for Chromium)
    libavcodec59 \
    libavformat59 \
    libavutil57 \
    xvfb && \
    rm -rf /var/lib/apt/lists/* && \
    # Make `python` resolve to python3 so skills can call either name
    ln -sfn /usr/bin/python3 /usr/local/bin/python && \
    mkdir -p /data /data/python-envs /home/node/.openclaw /home/node/.bun /home/node/.cache/qmd && \
    ln -sfn /data/qmd-models /home/node/.cache/qmd/models && \
    chown -R node:node /data /home/node/.openclaw /home/node/.bun /home/node/.cache

ARG ENTROPIC_INSTALL_DOCLING=0
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    openpyxl==3.1.5 \
    pytest==8.3.5 \
    python-pptx==1.0.2 && \
    if [ "$ENTROPIC_INSTALL_DOCLING" = "1" ]; then \
      python3 -m pip install --no-cache-dir --break-system-packages 'docling>=2.64,<3'; \
    fi

# Install patchright's patched Chromium:
# 1. Symlink to /usr/bin/chromium (OpenClaw's findChromeExecutableLinux() searches there)
# 2. Copy browsers to /opt/patchright-browsers/ so entrypoint can symlink into
#    PLAYWRIGHT_BROWSERS_PATH (/data/playwright/) for patchright's chromium.launch()
RUN npx patchright@latest install --no-shell chromium && \
    cp -a /root/.cache/ms-playwright /opt/patchright-browsers && \
    chmod -R a+rX /opt/patchright-browsers && \
    CHROME_BIN=$(find /opt/patchright-browsers -name 'chrome' -type f | head -1) && \
    if [ -n "$CHROME_BIN" ]; then ln -sfn "$CHROME_BIN" /usr/bin/chromium; fi && \
    rm -rf /root/.cache/ms-playwright /tmp/.npm /tmp/patchright-*

ENV BUN_INSTALL=/data/.bun
# Python user installs land in /data/.local so they survive container restarts
# (the node user's HOME is /home/node but /data is the persistent volume)
ENV PYTHONUSERBASE=/data/.local
ENV PATH="/data/.bun/bin:/data/.local/bin:${PATH}"

WORKDIR /app

# Copy OpenClaw package metadata and deps first (stable for caching)
COPY --chown=node:node package.json ./package.json
COPY --chown=node:node node_modules ./node_modules
COPY --chown=node:node all-extension-runtime-deps.txt ./all-extension-runtime-deps.txt
COPY --chown=node:node docs ./docs
COPY --chown=node:node extensions ./extensions
COPY --chown=node:node browser-service ./browser-service

# Copy OpenClaw dist last (changes most often)
COPY --chown=node:node dist ./dist

# Copy bundled skills (seeded into /data/skills/ at startup by entrypoint)
COPY --chown=node:node bundled-skills /app/bundled-skills

# Upstream's compiled root dist can statically import SDKs owned by optional
# channel extensions, even when Nova chooses not to ship those extensions in the
# runtime image. Install a compatibility dependency list generated from all
# upstream extension manifests so /app/dist stays resolvable without modifying
# upstream OpenClaw itself.
RUN EXT_DEPS="$(tr '\n' ' ' </app/all-extension-runtime-deps.txt)" && \
    if [ -n "$EXT_DEPS" ]; then \
      echo "Installing upstream extension compatibility deps into root node_modules..." && \
      npm install --omit=dev --ignore-scripts --legacy-peer-deps --package-lock=false --no-save $EXT_DEPS; \
    fi

# Install bundled skill dependencies (runs as root before USER node)
RUN for skill in /app/bundled-skills/*/; do \
      if [ -f "$skill/package.json" ]; then \
        echo "Installing deps for $(basename "$skill")..." && \
        cd "$skill" && npm install --omit=dev && cd /; \
      fi; \
    done

RUN if [ -f /app/browser-service/package.json ]; then \
      cd /app/browser-service && npm install --omit=dev && cd /; \
    fi

RUN mkdir -p /app/node_modules/osc-progress && \
    printf '{"name":"osc-progress","type":"module","exports":"./index.js"}\n' > /app/node_modules/osc-progress/package.json && \
    printf 'export function supportsOscProgress() { return false; }\nexport function createOscProgressController() { return { start() {}, update() {}, done() {}, fail() {} }; }\n' > /app/node_modules/osc-progress/index.js

# The compiled root dist imports Discord channel helpers directly. The Discord
# extension vendors @buape/carbon under its own node_modules, so expose that
# package at the root resolver location too.
RUN if [ -d /app/dist/extensions/discord/node_modules/@buape/carbon ]; then \
      mkdir -p /app/node_modules/@buape && \
      ln -sfn /app/dist/extensions/discord/node_modules/@buape/carbon /app/node_modules/@buape/carbon; \
      node -e 'const fs=require("fs"); const p="/app/dist/extensions/discord/node_modules/@buape/carbon/package.json"; const pkg=JSON.parse(fs.readFileSync(p,"utf8")); for (const key of [".","./*","./adapters/*"]) { if (pkg.exports?.[key]?.import && !pkg.exports[key].require) pkg.exports[key].require = pkg.exports[key].import; } fs.writeFileSync(p, JSON.stringify(pkg,null,2)+"\n");'; \
    fi

RUN PI_CODING_INDEX="/app/node_modules/@mariozechner/pi-coding-agent/dist/index.js" && \
    if ! grep -q 'Legacy Entropic compatibility exports' "$PI_CODING_INDEX"; then \
      printf '\n// Legacy Entropic compatibility exports.\nimport { createCodingTools as __entropicCreateCodingTools, createReadTool as __entropicCreateReadTool } from "./core/sdk.js";\nexport const codingTools = __entropicCreateCodingTools(process.cwd());\nexport const readTool = __entropicCreateReadTool(process.cwd());\n' >> "$PI_CODING_INDEX"; \
    fi

# Venice/OpenRouter rejects OpenAI-compatible completion requests with an empty
# tools array. OpenClaw can create tool-history turns for client-side tools such
# as browser, so omit the field instead of sending `tools: []`.
RUN node <<'NODE'
const fs = require("fs");
const path = require("path");

const distDir = "/app/dist";
const streamFile = fs.readdirSync(distDir).find((file) => /^anthropic-vertex-stream-.*\.js$/.test(file));
if (!streamFile) throw new Error("anthropic-vertex-stream bundle not found");
const filePath = path.join(distDir, streamFile);
let source = fs.readFileSync(filePath, "utf8");
source = source.replace(
	"} else if (hasToolHistory(context.messages)) params.tools = [];",
	"}"
);
source = source.replace(
	"if (context.tools) params.tools = convertAnthropicTools(context.tools, isOAuthToken);",
	"if (context.tools?.length) params.tools = convertAnthropicTools(context.tools, isOAuthToken);"
);
source = source.replace(
	"if (context.tools) params.tools = convertResponsesTools(context.tools, { strict: resolveOpenAIStrictToolSetting(model, { transport: \"stream\" }) });",
	"if (context.tools?.length) params.tools = convertResponsesTools(context.tools, { strict: resolveOpenAIStrictToolSetting(model, { transport: \"stream\" }) });"
);
source = source.replace(
	"if (context.tools) {\n\t\tparams.tools = convertTools(context.tools, compat, model);",
	"if (context.tools?.length) {\n\t\tparams.tools = convertTools(context.tools, compat, model);"
);
source = source.replace(
	`function convertTools(tools, compat, model) {
\tconst strict = resolveOpenAIStrictToolFlagForInventory(tools, resolveOpenAIStrictToolSetting(model, {
\t\ttransport: "stream",
\t\tsupportsStrictMode: compat?.supportsStrictMode
\t}));
\treturn tools.map((tool) => ({
\t\ttype: "function",
\t\tfunction: {
\t\t\tname: tool.name,
\t\t\tdescription: tool.description,
\t\t\tparameters: normalizeOpenAIStrictToolParameters(tool.parameters, strict === true),
\t\t\t...strict === void 0 ? {} : { strict }
\t\t}
\t}));
}`,
	`function convertTools(tools, compat, model) {
\tconst strict = resolveOpenAIStrictToolFlagForInventory(tools, resolveOpenAIStrictToolSetting(model, {
\t\ttransport: "stream",
\t\tsupportsStrictMode: compat?.supportsStrictMode
\t}));
\treturn tools.map((tool) => {
\t\tconst converted = {
\t\t\ttype: "function",
\t\t\tfunction: {
\t\t\t\tname: tool.name,
\t\t\t\tdescription: tool.description,
\t\t\t\tparameters: normalizeOpenAIStrictToolParameters(tool.parameters, strict === true),
\t\t\t\t...strict === void 0 ? {} : { strict }
\t\t\t}
\t\t};
\t\tObject.defineProperty(converted, "name", { value: tool.name });
\t\tObject.defineProperty(converted, "run", {
\t\t\tvalue: async (input) => {
\t\t\t\tif (typeof tool.run === "function") return await tool.run(input);
\t\t\t\tif (typeof tool.execute === "function") return await tool.execute("run_" + randomUUID(), input);
\t\t\t\tthrow new Error("Tool has no executable handler");
\t\t\t}
\t\t});
\t\treturn converted;
\t});
}`
);
for (const forbidden of [
	"} else if (hasToolHistory(context.messages)) params.tools = [];",
	"if (context.tools) params.tools = convertAnthropicTools(context.tools, isOAuthToken);",
	"if (context.tools) params.tools = convertResponsesTools(context.tools, { strict: resolveOpenAIStrictToolSetting(model, { transport: \"stream\" }) });",
	"if (context.tools) {\n\t\tparams.tools = convertTools(context.tools, compat, model);"
]) {
	if (source.includes(forbidden)) throw new Error(`Venice empty-tools compatibility patch missed: ${forbidden}`);
}
for (const required of [
	"Object.defineProperty(converted, \"name\"",
	"Object.defineProperty(converted, \"run\""
]) {
	if (!source.includes(required)) throw new Error(`Venice OpenAI tool runner compatibility patch missed: ${required}`);
}
fs.writeFileSync(filePath, source);
NODE

RUN node <<'NODE'
const fs = require("fs");
const path = require("path");

const distDir = "/app/dist";
const contextFile = fs.readdirSync(distDir).find((file) => /^model-context-tokens-.*\.js$/.test(file));
if (!contextFile) throw new Error("model-context-tokens bundle not found");
const filePath = path.join(distDir, contextFile);
let source = fs.readFileSync(filePath, "utf8");
source = source.replace(
	`function splitSdkTools(options) {
\tconst { tools } = options;
\treturn {
\t\tbuiltInTools: [],
\t\tcustomTools: toToolDefinitions(tools)
\t};
}`,
	`function splitSdkTools(options) {
\tconst { tools } = options;
\tconst definitions = toToolDefinitions(tools);
\treturn {
\t\tbuiltInTools: [],
\t\tcustomTools: definitions
\t};
}`
);
const marker = "const beforeHookWrapped = isToolWrappedWithBeforeToolCallHook(tool);";
if (!source.includes("function normalizeEntropicProviderToolRunInput(toolName, input)")) {
	source = source.replace(marker, `const beforeHookWrapped = isToolWrappedWithBeforeToolCallHook(tool);
\t\tconst runProviderTool = async (input) => {
\t\t\tconst toolCallId = "run_" + randomUUID();
\t\t\tconst normalizedInput = normalizeEntropicProviderToolRunInput(name, input);
\t\t\tlet executeParams = normalizedInput;
\t\t\ttry {
\t\t\t\tif (!beforeHookWrapped) {
\t\t\t\t\tconst hookOutcome = await runBeforeToolCallHook({
\t\t\t\t\t\ttoolName: name,
\t\t\t\t\t\tparams: normalizedInput,
\t\t\t\t\t\ttoolCallId
\t\t\t\t\t});
\t\t\t\t\tif (hookOutcome.blocked) throw new Error(hookOutcome.reason);
\t\t\t\t\texecuteParams = hookOutcome.params;
\t\t\t\t}
\t\t\t\treturn normalizeToolExecutionResult({
\t\t\t\t\ttoolName: normalizedName,
\t\t\t\t\tresult: await tool.execute(toolCallId, executeParams)
\t\t\t\t});
\t\t\t} catch (err) {
\t\t\t\tconst described = describeToolExecutionError(err);
\t\t\t\tlogError(\`[tools] \${normalizedName} failed: \${described.message}\`);
\t\t\t\treturn buildToolExecutionErrorResult({
\t\t\t\t\ttoolName: normalizedName,
\t\t\t\t\tmessage: described.message
\t\t\t\t});
\t\t\t}
\t\t};`);
	source = source.replace(
		"execute: async (...args) => {",
		"run: runProviderTool,\n\t\t\texecute: async (...args) => {"
	);
	source = source.replace(
		"//#endregion\n//#region src/agents/session-file-repair.ts",
		`function normalizeEntropicProviderToolRunInput(toolName, input) {
\tif (toolName === "browser" && typeof input === "string") {
\t\tconst trimmed = input.trim();
\t\tif (/^https?:\\/\\//i.test(trimmed)) return { action: "open", url: trimmed };
\t}
\treturn coerceParamsRecord(input);
}
//#endregion
//#region src/agents/session-file-repair.ts`
	);
}
for (const required of [
	"builtInTools: []",
	"customTools: definitions",
	"run: runProviderTool",
	"function normalizeEntropicProviderToolRunInput(toolName, input)"
]) {
	if (!source.includes(required)) throw new Error(`Provider tool run compatibility patch missed: ${required}`);
}
fs.writeFileSync(filePath, source);
NODE

RUN node <<'NODE'
const fs = require("fs");
const path = require("path");

const distDir = "/app/dist";
const contextFile = fs.readdirSync(distDir).find((file) => /^model-context-tokens-.*\.js$/.test(file));
if (!contextFile) throw new Error("model-context-tokens bundle not found");
const filePath = path.join(distDir, contextFile);
let source = fs.readFileSync(filePath, "utf8");

if (!source.includes("function stripEntropicAudioTranscriptPayloads(messages)")) {
	source = source.replace(
		"function estimateMessageChars$1(msg) {",
		`function isEntropicAudioContentBlock(block) {
\treturn !!block && typeof block === "object" && (block.type === "audio" || block.type === "input_audio");
}
function stripEntropicAudioTranscriptPayloads(messages) {
\tif (!Array.isArray(messages) || messages.length === 0) return messages;
\tlet changed = false;
\tconst stripped = [];
\tfor (const message of messages) {
\t\tif (!message || typeof message !== "object" || !Array.isArray(message.content)) {
\t\t\tstripped.push(message);
\t\t\tcontinue;
\t\t}
\t\tconst nextContent = message.content.filter((block) => !isEntropicAudioContentBlock(block));
\t\tif (nextContent.length === message.content.length) {
\t\t\tstripped.push(message);
\t\t\tcontinue;
\t\t}
\t\tchanged = true;
\t\tconst visibleText = nextContent.map((block) => block && typeof block === "object" && block.type === "text" && typeof block.text === "string" ? block.text : "").join("").trim();
\t\tif (nextContent.length === 0) continue;
\t\tif (message.role === "assistant" && /^Audio reply$/i.test(visibleText)) continue;
\t\tstripped.push({ ...message, content: nextContent });
\t}
\treturn changed ? stripped : messages;
}
function estimateMessageChars$1(msg) {`
	);
	source = source.replaceAll(
		"else chars += estimateUnknownChars(block);",
		"else if (isEntropicAudioContentBlock(block)) chars += 128;\n\t\telse chars += estimateUnknownChars(block);"
	);
	source = source.replace(
		"const withInterSessionMarkers = annotateInterSessionUserMessages(params.messages);",
		"const withInterSessionMarkers = annotateInterSessionUserMessages(stripEntropicAudioTranscriptPayloads(params.messages));"
	);
}
for (const required of [
	"function stripEntropicAudioTranscriptPayloads(messages)",
	"if (message.role === \"assistant\" && /^Audio reply$/i.test(visibleText)) continue;",
	"stripEntropicAudioTranscriptPayloads(params.messages)"
]) {
	if (!source.includes(required)) throw new Error(`Audio transcript replay sanitization patch missed: ${required}`);
}
fs.writeFileSync(filePath, source);
NODE

RUN node <<'NODE'
const fs = require("fs");
const path = require("path");

const distDir = "/app/dist";
const runnerFile = fs.readdirSync(distDir).find((file) => /^pi-embedded-runner-.*\.js$/.test(file));
if (!runnerFile) throw new Error("pi-embedded-runner bundle not found");
const filePath = path.join(distDir, runnerFile);
let source = fs.readFileSync(filePath, "utf8");
const before = source;
source = source.replace(
	/\n(\t+)tools: builtInTools,\n\1customTools: allCustomTools,/g,
	"\n$1...(builtInTools.length > 0 ? { tools: builtInTools } : {}),\n$1customTools: allCustomTools,"
);
if (source === before) throw new Error("Embedded runner createAgentSession tool allow-list call site not found");
for (const required of [
	"...(builtInTools.length > 0 ? { tools: builtInTools } : {})",
	"const allCustomTools = [...customTools, ...clientToolDefs];"
]) {
	if (!source.includes(required)) throw new Error(`Embedded runner tool allow-list compatibility patch missed: ${required}`);
}
fs.writeFileSync(filePath, source);
NODE

RUN chmod +x /app/browser-service/office_tools.py && \
    ln -sfn /app/browser-service/office_tools.py /usr/local/bin/entropic-office

# Fix clipboard module for ARM64 Linux (create stub)
RUN echo "module.exports = { read: () => '', write: () => {}, readSync: () => '', writeSync: () => {}, clear: () => {}, clearSync: () => {} };" > /app/node_modules/.pnpm/@mariozechner+clipboard@0.3.0/node_modules/@mariozechner/clipboard/index.js || true

# Fix sharp native bindings for Linux when node_modules were materialized outside
# the final image. Pick the linux binding that matches the image architecture
# instead of assuming an arm64 host.
RUN SHARP_PNPM="$(find /app/node_modules/.pnpm -maxdepth 1 -name 'sharp@*' -type d | head -1)" && \
    SHARP_VER="$(basename "$SHARP_PNPM" | sed 's/sharp@//')" && \
    SHARP_IMG_DIR="$SHARP_PNPM/node_modules/@img" && \
    TARGET_ARCH="$(dpkg --print-architecture)" && \
    case "$TARGET_ARCH" in \
      amd64) SHARP_SUFFIX="linux-x64" ;; \
      arm64) SHARP_SUFFIX="linux-arm64" ;; \
      *) SHARP_SUFFIX="" ;; \
    esac && \
    LIBVIPS_VER="$(find /app/node_modules/.pnpm -maxdepth 1 -type d -name "@img+sharp-libvips-*@*" | head -1 | sed 's/.*@//')" && \
    echo "sharp=$SHARP_VER libvips=$LIBVIPS_VER arch=$TARGET_ARCH suffix=$SHARP_SUFFIX img_dir=$SHARP_IMG_DIR" && \
    if [ -d "$SHARP_IMG_DIR" ] && [ -n "$SHARP_VER" ] && [ -n "$SHARP_SUFFIX" ]; then \
      cd /tmp && mkdir sharp-fix && cd sharp-fix && \
      npm init -y --silent 2>/dev/null && \
      npm install "@img/sharp-$SHARP_SUFFIX@$SHARP_VER" "@img/sharp-libvips-$SHARP_SUFFIX@${LIBVIPS_VER:-1.2.4}" 2>&1 && \
      ls -la node_modules/@img/ && \
      cp -a "node_modules/@img/sharp-$SHARP_SUFFIX" "$SHARP_IMG_DIR/sharp-$SHARP_SUFFIX" && \
      cp -a "node_modules/@img/sharp-libvips-$SHARP_SUFFIX" "$SHARP_IMG_DIR/sharp-libvips-$SHARP_SUFFIX" && \
      echo "Installed sharp $SHARP_SUFFIX bindings into $SHARP_IMG_DIR" && \
      cd / && rm -rf /tmp/sharp-fix; \
    fi

# Fix @snazzah/davey native bindings for Linux when node_modules were
# materialized on macOS. The optional platform package is selected at install
# time, so copying host node_modules into the runtime image can miss the Linux
# binary entirely and cause the gateway to crash on boot.
RUN DAVEY_PNPM="$(find /app/node_modules/.pnpm -maxdepth 1 -name '@snazzah+davey@*' -type d | head -1)" && \
    DAVEY_VER="$(basename "$DAVEY_PNPM" | sed 's/@snazzah+davey@//')" && \
    DAVEY_SCOPE_DIR="/app/node_modules/.pnpm/node_modules/@snazzah" && \
    TARGET_ARCH="$(dpkg --print-architecture)" && \
    case "$TARGET_ARCH" in \
      amd64) DAVEY_SUFFIX="linux-x64-gnu" ;; \
      arm64) DAVEY_SUFFIX="linux-arm64-gnu" ;; \
      *) DAVEY_SUFFIX="" ;; \
    esac && \
    echo "davey=$DAVEY_VER arch=$TARGET_ARCH suffix=$DAVEY_SUFFIX scope_dir=$DAVEY_SCOPE_DIR" && \
    if [ -d "$DAVEY_SCOPE_DIR" ] && [ -n "$DAVEY_VER" ] && [ -n "$DAVEY_SUFFIX" ]; then \
      cd /tmp && mkdir davey-fix && cd davey-fix && \
      npm init -y --silent 2>/dev/null && \
      npm install "@snazzah/davey-$DAVEY_SUFFIX@$DAVEY_VER" 2>&1 && \
      mkdir -p "$DAVEY_SCOPE_DIR" && \
      cp -a "node_modules/@snazzah/davey-$DAVEY_SUFFIX" "$DAVEY_SCOPE_DIR/davey-$DAVEY_SUFFIX" && \
      echo "Installed davey $DAVEY_SUFFIX binding into $DAVEY_SCOPE_DIR" && \
      cd / && rm -rf /tmp/davey-fix; \
    fi

# Switch to non-root user
USER node

# QMD is installed on-demand at runtime when enabled in Settings.
ENV NODE_PATH="/data/.bun/install/global/node_modules:/home/node/.bun/install/global/node_modules"

# Health check
# Use the shallow gateway probe endpoints that upstream exposes specifically
# for container/runtime liveness. Routes like /__openclaw__/canvas/ now carry
# auth/capability semantics and can fail during normal startup even when the
# gateway process itself is healthy enough to finish booting.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s \
    CMD sh -c 'curl -fsS "http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}/healthz" >/dev/null || exit 1'

EXPOSE 18789 19791 19793

# Set credentials directory to persistent storage
ENV OPENCLAW_OAUTH_DIR=/data/credentials

# Entrypoint script that creates auth from env vars, then starts gateway
COPY --chown=node:node entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
