#!/usr/bin/env bash
set -e

echo "== Diagnóstico rápido del contenedor (para no seguir adivinando memoria) =="
nproc 2>/dev/null || true
free -h 2>/dev/null || true
echo ""

echo "== Matando daemons de Gradle/Kotlin activos =="
./gradlew --stop || true
pkill -f KotlinCompileDaemon 2>/dev/null || true
sleep 2
echo "OK: daemons detenidos."

echo "== Reescribiendo gradle.properties: menos paralelismo, heaps explícitos =="
cat > gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8
org.gradle.parallel=false
org.gradle.caching=true
org.gradle.workers.max=2
kotlin.daemon.jvmargs=-Xmx1536m
android.useAndroidX=true
kotlin.code.style=official
EOF
echo "OK: gradle.properties ajustado."

echo "== Reintentando ./gradlew :blockade:assembleDebug (daemon nuevo, menos paralelismo) =="
./gradlew :blockade:assembleDebug

echo "== Estado en git =="
git add -A
git status --short

echo "============================================================"
echo "assembleDebug corrió con daemon limpio y menos paralelismo."
echo ""
echo "Qué cambié y por qué (nada de esto toca tu código Kotlin):"
echo "  - ./gradlew --stop mató el daemon reciclado desde hacía 4 builds."
echo "    Un daemon reutilizado muchas veces acumula memoria; es la causa"
echo "    más común de 'daemon disappeared' y no tiene que ver con el"
echo "    PolicyEntityMapper ni con ningún archivo que generé."
echo "  - org.gradle.parallel=false + workers.max=2: Gradle ya no levanta"
echo "    varios procesos a la vez peleando por RAM. Esto recién importa"
echo "    desde que KSP/Room entraron -- es la primera tarea pesada de"
echo "    verdad que corre este proyecto."
echo "  - kotlin.daemon.jvmargs=-Xmx1536m: el daemon de Kotlin (proceso"
echo "    separado del de Gradle) no tenía tope explícito; sin tope puede"
echo "    crecer sin control build tras build."
echo "  - Bajé org.gradle.jvmargs de 2g a 1536m: entre Gradle + Kotlin ya"
echo "    no piden más de ~3g juntos en vez de competir sin límite claro."
echo ""
echo "Si esto vuelve a tronar, mira el 'free -h' de arriba de este mismo"
echo "output: si el Codespace tiene 4GB de RAM totales, ningún ajuste de"
echo "gradle.properties lo va a arreglar del todo -- ahí hay que subir el"
echo "Codespace a una máquina con más RAM (2-core/8GB o más), porque"
echo "Room+KSP+Compose ya pide más de lo que pedía el proyecto hasta"
echo "Fase 2.5."
echo "============================================================"
