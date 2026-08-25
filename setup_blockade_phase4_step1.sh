#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_blockade_phase4_step1.sh
#
# Fase 4, primer paso (tal como lo definio ChatGPT):
#   - Interfaz ForegroundAppProvider (suspend fun getForegroundPackage(): String?)
#   - Implementacion AndroidForegroundAppProvider basada en
#     UsageStatsManager.queryEvents(...) + UsageEvents.Event.ACTIVITY_RESUMED
#   - Un Clock inyectable en vez de System.currentTimeMillis() directo,
#     para que la logica sea testeable sin dispositivo real
#   - Conexion en AppContainer, mismo patron que installedAppsProvider
#   - Tests unitarios SOLO de la logica pura de seleccion de evento
#     (sin tocar UsageStatsManager real, que requiere instrumented test)
#
# NO toca (deliberadamente, tal como pidio ChatGPT):
#   - AccessibilityService
#   - QuickBlockScreen
#   - enforcement / conexion con PolicyRepository
#
# El permiso PACKAGE_USAGE_STATS YA estaba declarado en el
# AndroidManifest.xml (verificado contra el repo real, commit
# fead668) - este script NO lo vuelve a agregar.
#
# VERIFICADO CONTRA EL REPO REAL, commit fead668, rama main:
#   - blockade/src/main/java/com/irrovicas/blockade/platform/apps/
#     (InstalledAppsProvider.kt / AndroidInstalledAppsProvider.kt)
#     usados como referencia de estilo (interfaz simple +
#     implementacion que recibe Context por constructor, sin
#     framework de DI)
#   - blockade/src/main/java/com/irrovicas/blockade/di/AppContainer.kt
#     usado para saber donde y como conectar la nueva dependencia
#   - blockade/src/main/AndroidManifest.xml
#     confirma que PACKAGE_USAGE_STATS ya esta declarado
# ============================================================

REPO_ROOT="$(pwd)"
BASE="$REPO_ROOT/blockade/src/main/java/com/irrovicas/blockade"
TEST_BASE="$REPO_ROOT/blockade/src/test/java/com/irrovicas/blockade"
APP_CONTAINER="$BASE/di/AppContainer.kt"

echo "== Validando precondiciones =="

if [ ! -d "$REPO_ROOT/blockade" ]; then
    echo "ERROR: no se encontro el modulo blockade/ desde $(pwd)"
    echo "       Corre este script desde la raiz del repo (PROYECTO/)."
    exit 1
fi

if [ ! -f "$APP_CONTAINER" ]; then
    echo "ERROR: no se encontro $APP_CONTAINER"
    echo "       El repo cambio respecto a lo verificado - abortando en vez de adivinar."
    exit 1
fi

if [ -e "$BASE/platform/foreground" ]; then
    echo "ERROR: $BASE/platform/foreground ya existe."
    echo "       Este paso de Fase 4 parece haberse corrido antes - abortando para no pisar nada."
    exit 1
fi

if ! grep -Fq 'val installedAppsProvider: InstalledAppsProvider =' "$APP_CONTAINER"; then
    echo "ERROR: AppContainer.kt no tiene la forma esperada (installedAppsProvider)."
    echo "       El archivo cambio respecto a lo verificado - abortando en vez de adivinar."
    exit 1
fi

echo "OK: estructura del repo coincide con lo verificado (commit fead668)."

echo "== Creando paquete platform/foreground =="
mkdir -p "$BASE/platform/foreground"
mkdir -p "$TEST_BASE/platform/foreground"

echo "== Escribiendo Clock.kt (abstraccion minima de tiempo, para tests) =="
cat > "$BASE/platform/foreground/Clock.kt" << 'EOF'
package com.irrovicas.blockade.platform.foreground

/**
 * Abstraccion minima sobre la hora actual, para que la logica de
 * ForegroundAppProvider no dependa directamente de
 * System.currentTimeMillis() y se pueda testear con un reloj falso.
 */
interface Clock {

    fun currentTimeMillis(): Long
}

class SystemClock : Clock {

    override fun currentTimeMillis(): Long = System.currentTimeMillis()
}
EOF

echo "== Escribiendo ForegroundAppProvider.kt (interfaz) =="
cat > "$BASE/platform/foreground/ForegroundAppProvider.kt" << 'EOF'
package com.irrovicas.blockade.platform.foreground

/**
 * Contrato para obtener el paquete de la aplicacion actualmente en
 * foreground. No implementa bloqueo ni enforcement: solo responde
 * la pregunta "que app esta en primer plano ahora mismo".
 *
 * El enforcement (AccessibilityService u otro mecanismo) es una
 * capa separada que se conectara despues, tal como se acordo con
 * ChatGPT para no mezclar ambas responsabilidades.
 */
interface ForegroundAppProvider {

    suspend fun getForegroundPackage(): String?
}
EOF

echo "== Escribiendo ForegroundEventSelector.kt (logica pura, testeable sin Android) =="
cat > "$BASE/platform/foreground/ForegroundEventSelector.kt" << 'EOF'
package com.irrovicas.blockade.platform.foreground

/**
 * Representacion minima de un evento de uso, desacoplada de
 * android.app.usage.UsageEvents.Event para poder testear la logica
 * de seleccion sin depender del framework de Android.
 *
 * eventType usa las mismas constantes de UsageEvents.Event
 * (ACTIVITY_RESUMED = 1) para que el mapeo en la implementacion
 * Android sea directo.
 */
data class ForegroundEvent(
    val packageName: String,
    val eventType: Int,
    val timestamp: Long,
)

/**
 * Logica pura: dado un listado de eventos ya filtrado por ventana de
 * tiempo, decide cual es el paquete en foreground.
 *
 * Regla: se queda con el ULTIMO evento de tipo ACTIVITY_RESUMED.
 * Eventos de otro tipo se ignoran. Si no hay ninguno, devuelve null.
 */
object ForegroundEventSelector {

    const val ACTIVITY_RESUMED = 1

    fun selectForegroundPackage(events: List<ForegroundEvent>): String? {
        return events
            .filter { it.eventType == ACTIVITY_RESUMED }
            .maxByOrNull { it.timestamp }
            ?.packageName
    }
}
EOF

echo "== Escribiendo AndroidForegroundAppProvider.kt (implementacion con UsageStatsManager) =="
cat > "$BASE/platform/foreground/AndroidForegroundAppProvider.kt" << 'EOF'
package com.irrovicas.blockade.platform.foreground

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context

/**
 * Implementacion Android de ForegroundAppProvider basada en
 * UsageStatsManager.queryEvents(...).
 *
 * Importante: UsageStatsManager por si solo NO bloquea aplicaciones,
 * solo permite consultar que paquete estuvo en foreground. El
 * enforcement (AccessibilityService u otro mecanismo) es una capa
 * separada que se construira despues.
 *
 * Requiere el permiso PACKAGE_USAGE_STATS, que es un permiso
 * especial: declararlo en el manifest no otorga el acceso, el
 * usuario debe habilitarlo manualmente desde
 * Settings.ACTION_USAGE_ACCESS_SETTINGS. Ese flujo de UI no se
 * implementa todavia en este paso.
 */
class AndroidForegroundAppProvider(
    private val context: Context,
    private val clock: Clock = SystemClock(),
    private val windowMillis: Long = DEFAULT_WINDOW_MILLIS,
) : ForegroundAppProvider {

    override suspend fun getForegroundPackage(): String? {
        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return null

        val now = clock.currentTimeMillis()
        val events = usageStatsManager.queryEvents(now - windowMillis, now)

        val collected = mutableListOf<ForegroundEvent>()
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            collected.add(
                ForegroundEvent(
                    packageName = event.packageName,
                    eventType = event.eventType,
                    timestamp = event.timeStamp,
                ),
            )
        }

        return ForegroundEventSelector.selectForegroundPackage(collected)
    }

    private companion object {
        const val DEFAULT_WINDOW_MILLIS = 10_000L
    }
}
EOF

echo "== Conectando foregroundAppProvider en AppContainer.kt =="

# Agrega el import justo despues del import de InstalledAppsProvider,
# para mantener el bloque de imports de platform.* junto.
sed -i \
    "/^import com.irrovicas.blockade.platform.apps.InstalledAppsProvider\$/a import com.irrovicas.blockade.platform.foreground.AndroidForegroundAppProvider\nimport com.irrovicas.blockade.platform.foreground.ForegroundAppProvider" \
    "$APP_CONTAINER"

# Agrega la propiedad justo despues de installedAppsProvider, mismo
# estilo (val ... : Interfaz = Implementacion(context)).
python3 - "$APP_CONTAINER" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

anchor = "    val installedAppsProvider: InstalledAppsProvider =\n        AndroidInstalledAppsProvider(context)\n"

if anchor not in content:
    print("ERROR: no se encontro el bloque exacto de installedAppsProvider en AppContainer.kt")
    sys.exit(1)

addition = (
    anchor
    + "\n"
    + "    val foregroundAppProvider: ForegroundAppProvider =\n"
    + "        AndroidForegroundAppProvider(context)\n"
)

content = content.replace(anchor, addition)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: foregroundAppProvider agregado a AppContainer.kt")
PYEOF

echo "== Resultado (AppContainer.kt completo) =="
cat "$APP_CONTAINER"
echo ""

echo "== Escribiendo test: ForegroundEventSelectorTest.kt =="
cat > "$TEST_BASE/platform/foreground/ForegroundEventSelectorTest.kt" << 'EOF'
package com.irrovicas.blockade.platform.foreground

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Tests de la logica pura de seleccion de evento en foreground.
 * No dependen de UsageStatsManager ni de un dispositivo Android:
 * cubren exactamente los casos que se acordaron con ChatGPT.
 */
class ForegroundEventSelectorTest {

    private val activityResumed = ForegroundEventSelector.ACTIVITY_RESUMED
    private val otherEventType = 99

    @Test
    fun `returns null when there are no events`() {
        val result = ForegroundEventSelector.selectForegroundPackage(emptyList())

        assertNull(result)
    }

    @Test
    fun `returns package of the last ACTIVITY_RESUMED event`() {
        val events = listOf(
            ForegroundEvent("com.app.one", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.two", activityResumed, timestamp = 2_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.two", result)
    }

    @Test
    fun `ignores events that are not ACTIVITY_RESUMED`() {
        val events = listOf(
            ForegroundEvent("com.app.one", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.two", otherEventType, timestamp = 5_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.one", result)
    }

    @Test
    fun `handles multiple app switches and keeps the most recent one`() {
        val events = listOf(
            ForegroundEvent("com.app.a", activityResumed, timestamp = 1_000L),
            ForegroundEvent("com.app.b", otherEventType, timestamp = 1_500L),
            ForegroundEvent("com.app.b", activityResumed, timestamp = 2_000L),
            ForegroundEvent("com.app.c", activityResumed, timestamp = 3_000L),
            ForegroundEvent("com.app.c", otherEventType, timestamp = 3_500L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertEquals("com.app.c", result)
    }

    @Test
    fun `returns null when only non-resumed events are present`() {
        val events = listOf(
            ForegroundEvent("com.app.one", otherEventType, timestamp = 1_000L),
            ForegroundEvent("com.app.two", otherEventType, timestamp = 2_000L),
        )

        val result = ForegroundEventSelector.selectForegroundPackage(events)

        assertNull(result)
    }
}
EOF

echo "== Deteniendo el daemon de Gradle antes de compilar (memoria limitada en Codespaces) =="
cd "$REPO_ROOT"
./gradlew --stop

echo ""
echo "== Corriendo ./gradlew :blockade:test =="
./gradlew :blockade:test

echo ""
echo "== Estado en git =="
git add -A
git status --short

echo ""
echo "== Diff exacto (sin paginador, para que no se corte el output) =="
git --no-pager diff --cached -- \
    "blockade/src/main/java/com/irrovicas/blockade/platform/foreground" \
    "blockade/src/main/java/com/irrovicas/blockade/di/AppContainer.kt" \
    "blockade/src/test/java/com/irrovicas/blockade/platform/foreground"

cat << 'MSG'
============================================================
Fase 4, Paso 1 completado: ForegroundAppProvider.

Se crearon (paquete platform/foreground):
  - Clock.kt                        (abstraccion de tiempo, testeable)
  - ForegroundAppProvider.kt        (interfaz)
  - ForegroundEventSelector.kt      (logica pura de seleccion de evento)
  - AndroidForegroundAppProvider.kt (implementacion con UsageStatsManager)

Se modifico:
  - di/AppContainer.kt              (agrega foregroundAppProvider,
                                      mismo patron que installedAppsProvider)

Se agrego test unitario (5 casos, logica pura, sin UsageStatsManager real):
  - ForegroundEventSelectorTest.kt

NO se toco (a proposito, coordinado con ChatGPT para este paso):
  - AndroidManifest.xml   (PACKAGE_USAGE_STATS ya estaba declarado)
  - BlockadeAccessibilityService.kt
  - QuickBlockScreen.kt
  - Ninguna conexion con PolicyRepository / enforcement

Revisa arriba el resultado de ./gradlew :blockade:test.
Si todo paso, commitea y sube:

  git commit -m "feat(blockade): add ForegroundAppProvider with UsageStatsManager"
  git push origin main

Con esto queda lista la primera primitiva de Fase 4 ("que paquete
esta en foreground ahora"). El siguiente paso natural es decidir el
mecanismo de enforcement (AccessibilityService u otro) que consuma
esta senal - eso todavia no se implementa aqui.
============================================================
MSG
