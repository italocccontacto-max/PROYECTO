#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_blockade_phase4_step2.sh
#
# Fase 4, segundo paso: enforcement real via BlockadeAccessibilityService.
#
# HALLAZGO CLAVE (verificado contra el repo real, no supuesto):
#   El motor de decision (PolicyEvaluator + EnforcementDecision +
#   PolicyEvaluationContext) YA EXISTE desde una fase anterior y ya
#   esta completo. Su propio KDoc dice explicitamente:
#     "El motor responde: Que debe hacerse?
#      El mecanismo Android respondera despues: Como lo hago?"
#   Esto es EXACTAMENTE lo que ChatGPT pidio para BlockEnforcer, asi
#   que este script NO reinventa una interfaz Policy simplificada -
#   conecta lo que ya esta construido.
#
# Se crea (paquete platform/enforcement, mismo patron que
# platform/apps y platform/foreground):
#   - BlockEnforcer.kt                  (interfaz)
#   - GlobalActionPerformer.kt          (fun interface, para poder
#                                        testear la decision sin
#                                        depender de un Service real)
#   - BlockEnforcementActionResolver.kt (logica pura: dado un
#                                        EnforcementDecision, decide
#                                        si corresponde actuar)
#   - AndroidBlockEnforcer.kt           (implementacion: usa
#                                        performGlobalAction(GLOBAL_ACTION_HOME))
#
# Se crea (paquete accessibility, junto al service existente):
#   - AccessibilityEventFilter.kt       (logica pura: dado un evento
#                                        crudo, decide si hay que
#                                        procesarlo y que packageName
#                                        usar - ignora eventos que no
#                                        son cambio de ventana y
#                                        eventos de la propia app,
#                                        mismo criterio de auto-exclusion
#                                        que ya usa AndroidInstalledAppsProvider)
#
# Se modifica:
#   - accessibility/BlockadeAccessibilityService.kt
#     Deja de ser un placeholder vacio. Pasa a:
#       1) En onServiceConnected(): obtener AppContainer desde
#          BlockadeApplication (mismo patron que MainActivity) y
#          empezar a observar observePolicies() en un CoroutineScope
#          propio del service.
#       2) En onAccessibilityEvent(): filtrar el evento, construir un
#          PolicyEvaluationContext con el packageName resuelto, pedirle
#          la decision a appContainer.policyEvaluator (YA EXISTE en
#          AppContainer, no se duplica), y si es Block, delegar en
#          BlockEnforcer.
#       3) En onDestroy(): cancelar el scope.
#
# Constantes de Android verificadas contra la documentacion oficial
# antes de escribir este script (no se asumieron de memoria):
#   - AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED = 32 (0x20)
#   - AccessibilityService.GLOBAL_ACTION_HOME se usa directamente
#     desde el SDK real (import), nunca como numero copiado a mano,
#     para no arriesgar un valor incorrecto.
#
# NO se toca (a proposito, mismo criterio que Fase 4 Paso 1):
#   - QuickBlockScreen.kt (sigue sin boton de accesibilidad - eso
#     queda para un paso de UI aparte, fuera de este script)
#   - AndroidManifest.xml / blockade_accessibility_service.xml
#     (ya declaran typeWindowStateChanged|typeWindowContentChanged,
#     no hace falta agregar nada)
#   - ForegroundAppProvider / AndroidForegroundAppProvider (Fase 4
#     Paso 1) - ChatGPT pidio dejarlo como mecanismo de consulta o
#     respaldo, no como señal primaria; este paso usa el packageName
#     que trae el propio AccessibilityEvent, tal como recomendo.
#
# VERIFICADO CONTRA EL REPO REAL antes de escribir este script:
#   - accessibility/BlockadeAccessibilityService.kt (placeholder vacio)
#   - res/xml/blockade_accessibility_service.xml
#   - domain/engine/EnforcementDecision.kt
#   - domain/engine/PolicyEvaluator.kt (incluye PolicyEvaluationContext)
#   - domain/repository/PolicyRepository.kt
#   - domain/model/BlockadePolicy.kt, BlockAction.kt, BlockTarget.kt
#   - domain/usecase/ObservePoliciesUseCase.kt
#   - di/AppContainer.kt (ya expone policyEvaluator y observePolicies)
#   - BlockadeApplication.kt, MainActivity.kt (patron de acceso a AppContainer)
# ============================================================

REPO_ROOT="$(pwd)"
BASE="$REPO_ROOT/blockade/src/main/java/com/irrovicas/blockade"
TEST_BASE="$REPO_ROOT/blockade/src/test/java/com/irrovicas/blockade"
SERVICE_FILE="$BASE/accessibility/BlockadeAccessibilityService.kt"

echo "== Validando precondiciones =="

if [ ! -d "$REPO_ROOT/blockade" ]; then
    echo "ERROR: no se encontro el modulo blockade/ desde $(pwd)"
    echo "       Corre este script desde la raiz del repo (PROYECTO/)."
    exit 1
fi

if [ ! -f "$SERVICE_FILE" ]; then
    echo "ERROR: no se encontro $SERVICE_FILE"
    echo "       El repo cambio respecto a lo verificado - abortando en vez de adivinar."
    exit 1
fi

if ! grep -Fq "// Enforcement engine placeholder." "$SERVICE_FILE"; then
    echo "ERROR: BlockadeAccessibilityService.kt no tiene el placeholder esperado."
    echo "       O ya fue modificado, o el archivo cambio - abortando en vez de sobreescribir a ciegas."
    exit 1
fi

if [ -e "$BASE/platform/enforcement" ]; then
    echo "ERROR: $BASE/platform/enforcement ya existe."
    echo "       Este paso parece haberse corrido antes - abortando para no pisar nada."
    exit 1
fi

if [ -e "$BASE/accessibility/AccessibilityEventFilter.kt" ]; then
    echo "ERROR: $BASE/accessibility/AccessibilityEventFilter.kt ya existe."
    exit 1
fi

if ! grep -Fq "val policyEvaluator =" "$BASE/di/AppContainer.kt"; then
    echo "ERROR: AppContainer.kt no expone policyEvaluator como se esperaba."
    exit 1
fi

if ! grep -Fq "val observePolicies =" "$BASE/di/AppContainer.kt"; then
    echo "ERROR: AppContainer.kt no expone observePolicies como se esperaba."
    exit 1
fi

echo "OK: estructura del repo coincide con lo verificado."

echo "== Creando paquete platform/enforcement =="
mkdir -p "$BASE/platform/enforcement"
mkdir -p "$TEST_BASE/platform/enforcement"
mkdir -p "$TEST_BASE/accessibility"

echo "== Escribiendo BlockEnforcer.kt (interfaz) =="
cat > "$BASE/platform/enforcement/BlockEnforcer.kt" << 'EOF'
package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision

/**
 * Mecanismo Android que hace efectiva una decision de bloqueo.
 *
 * El "que" ya lo respondio PolicyEvaluator (ver EnforcementDecision).
 * Esta interfaz responde el "como": que hace el dispositivo cuando
 * hay que bloquear.
 */
interface BlockEnforcer {

    fun enforce(decision: EnforcementDecision.Block)
}
EOF

echo "== Escribiendo GlobalActionPerformer.kt (seam testeable sobre performGlobalAction) =="
cat > "$BASE/platform/enforcement/GlobalActionPerformer.kt" << 'EOF'
package com.irrovicas.blockade.platform.enforcement

/**
 * Abstraccion minima sobre AccessibilityService.performGlobalAction(Int).
 *
 * Existe para que AndroidBlockEnforcer no dependa de una instancia
 * concreta de AccessibilityService, sino de esta interfaz funcional -
 * la propia service puede pasarse a si misma como referencia de
 * metodo (::performGlobalAction) porque la firma coincide exactamente.
 */
fun interface GlobalActionPerformer {

    fun performGlobalAction(action: Int): Boolean
}
EOF

echo "== Escribiendo BlockEnforcementActionResolver.kt (logica pura, testeable sin Android) =="
cat > "$BASE/platform/enforcement/BlockEnforcementActionResolver.kt" << 'EOF'
package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.model.BlockAction

/**
 * Logica pura: dado un EnforcementDecision, decide si corresponde
 * ejecutar el mecanismo de bloqueo (llevar al usuario fuera de la
 * app/contenido).
 *
 * Solo actua cuando la decision es Block y sus acciones incluyen
 * LAUNCH o FULL. Una politica que solo pide silenciar
 * NOTIFICATION no debe sacar al usuario de la app.
 */
object BlockEnforcementActionResolver {

    fun shouldEnforce(decision: EnforcementDecision): Boolean {
        if (decision !is EnforcementDecision.Block) {
            return false
        }

        return BlockAction.LAUNCH in decision.actions ||
            BlockAction.FULL in decision.actions
    }
}
EOF

echo "== Escribiendo AndroidBlockEnforcer.kt (implementacion) =="
cat > "$BASE/platform/enforcement/AndroidBlockEnforcer.kt" << 'EOF'
package com.irrovicas.blockade.platform.enforcement

import android.accessibilityservice.AccessibilityService
import com.irrovicas.blockade.domain.engine.EnforcementDecision

/**
 * Primera implementacion real de BlockEnforcer.
 *
 * Mecanismo MVP: cuando corresponde bloquear, saca al usuario de la
 * app/contenido llevandolo a la pantalla de inicio via
 * AccessibilityService.performGlobalAction(GLOBAL_ACTION_HOME).
 *
 * No intenta (todavia) mostrar un overlay explicativo ni distinguir
 * entre tipos de BlockTarget - eso puede refinarse en un paso
 * posterior sin cambiar el contrato de BlockEnforcer.
 */
class AndroidBlockEnforcer(
    private val globalActionPerformer: GlobalActionPerformer,
) : BlockEnforcer {

    override fun enforce(decision: EnforcementDecision.Block) {
        if (!BlockEnforcementActionResolver.shouldEnforce(decision)) {
            return
        }

        globalActionPerformer.performGlobalAction(
            AccessibilityService.GLOBAL_ACTION_HOME,
        )
    }
}
EOF

echo "== Escribiendo AccessibilityEventFilter.kt (logica pura, testeable sin Android) =="
cat > "$BASE/accessibility/AccessibilityEventFilter.kt" << 'EOF'
package com.irrovicas.blockade.accessibility

/**
 * Logica pura de interpretacion de un AccessibilityEvent crudo.
 *
 * Decide dos cosas a la vez:
 *   1) si el evento es relevante (cambio de ventana, no cualquier
 *      otro tipo de evento - el service tambien recibe
 *      typeWindowContentChanged, mucho mas ruidoso, y ese se ignora
 *      aqui antes de tocar el motor de decision);
 *   2) que packageName usar, excluyendo la propia app BLOCKADE
 *      (mismo criterio de auto-exclusion que ya usa
 *      AndroidInstalledAppsProvider contra context.packageName).
 *
 * TYPE_WINDOW_STATE_CHANGED = 32 replica el valor real de
 * android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
 * (verificado contra la documentacion oficial de Android), para que
 * esta clase no dependa del framework y se pueda testear en JVM puro.
 */
object AccessibilityEventFilter {

    const val TYPE_WINDOW_STATE_CHANGED = 32

    fun resolveForegroundPackage(
        eventType: Int,
        packageName: String?,
        ownPackageName: String,
    ): String? {
        if (eventType != TYPE_WINDOW_STATE_CHANGED) {
            return null
        }

        if (packageName.isNullOrBlank()) {
            return null
        }

        if (packageName == ownPackageName) {
            return null
        }

        return packageName
    }
}
EOF

echo "== Reescribiendo BlockadeAccessibilityService.kt (conectando el motor ya existente) =="
cat > "$SERVICE_FILE" << 'EOF'
package com.irrovicas.blockade.accessibility

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import com.irrovicas.blockade.BlockadeApplication
import com.irrovicas.blockade.di.AppContainer
import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.engine.PolicyEvaluationContext
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.platform.enforcement.AndroidBlockEnforcer
import com.irrovicas.blockade.platform.enforcement.BlockEnforcer
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Adaptador Android puro.
 *
 * Toda la logica de negocio vive fuera de esta clase:
 *   - AccessibilityEventFilter decide si el evento es relevante.
 *   - appContainer.policyEvaluator (ya existente) decide que hacer.
 *   - BlockEnforcer decide como hacerlo.
 *
 * Esta clase solo conecta esas tres piezas con los callbacks que
 * exige el sistema.
 */
class BlockadeAccessibilityService : AccessibilityService() {

    private val serviceScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var appContainer: AppContainer
    private lateinit var blockEnforcer: BlockEnforcer

    @Volatile
    private var currentPolicies: List<BlockadePolicy> = emptyList()

    override fun onServiceConnected() {
        super.onServiceConnected()

        appContainer =
            (application as BlockadeApplication).appContainer

        blockEnforcer =
            AndroidBlockEnforcer(
                globalActionPerformer = ::performGlobalAction,
            )

        serviceScope.launch {
            appContainer.observePolicies.execute().collect { policies ->
                currentPolicies = policies
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) {
            return
        }

        val foregroundPackage =
            AccessibilityEventFilter.resolveForegroundPackage(
                eventType = event.eventType,
                packageName = event.packageName?.toString(),
                ownPackageName = packageName,
            ) ?: return

        val context =
            PolicyEvaluationContext(
                now = Instant.now(),
                zoneId = ZoneId.systemDefault(),
                foregroundApplicationPackage = foregroundPackage,
            )

        val decision =
            appContainer.policyEvaluator.evaluate(
                policies = currentPolicies,
                context = context,
            )

        if (decision is EnforcementDecision.Block) {
            blockEnforcer.enforce(decision)
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
EOF

echo "== Resultado (BlockadeAccessibilityService.kt completo) =="
cat "$SERVICE_FILE"
echo ""

echo "== Escribiendo test: BlockEnforcementActionResolverTest.kt =="
cat > "$TEST_BASE/platform/enforcement/BlockEnforcementActionResolverTest.kt" << 'EOF'
package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BlockEnforcementActionResolverTest {

    private val target = BlockTarget.Application("com.example.blocked")

    @Test
    fun `does not enforce when decision is Allow`() {
        val result =
            BlockEnforcementActionResolver.shouldEnforce(
                EnforcementDecision.Allow,
            )

        assertFalse(result)
    }

    @Test
    fun `enforces when Block includes LAUNCH`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.LAUNCH),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }

    @Test
    fun `enforces when Block includes FULL`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.FULL),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }

    @Test
    fun `does not enforce when Block only includes NOTIFICATION`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.NOTIFICATION),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertFalse(result)
    }

    @Test
    fun `enforces when Block includes LAUNCH and NOTIFICATION together`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.LAUNCH, BlockAction.NOTIFICATION),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }
}
EOF

echo "== Escribiendo test: AccessibilityEventFilterTest.kt =="
cat > "$TEST_BASE/accessibility/AccessibilityEventFilterTest.kt" << 'EOF'
package com.irrovicas.blockade.accessibility

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AccessibilityEventFilterTest {

    private val windowStateChanged =
        AccessibilityEventFilter.TYPE_WINDOW_STATE_CHANGED
    private val otherEventType = 2048 // typeWindowContentChanged real
    private val ownPackage = "com.irrovicas.blockade"

    @Test
    fun `returns the package on a window state change from another app`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = "com.instagram.android",
            ownPackageName = ownPackage,
        )

        assertEquals("com.instagram.android", result)
    }

    @Test
    fun `ignores events that are not a window state change`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = otherEventType,
            packageName = "com.instagram.android",
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events with a null package name`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = null,
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events with a blank package name`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = "   ",
            ownPackageName = ownPackage,
        )

        assertNull(result)
    }

    @Test
    fun `ignores events coming from BLOCKADE itself`() {
        val result = AccessibilityEventFilter.resolveForegroundPackage(
            eventType = windowStateChanged,
            packageName = ownPackage,
            ownPackageName = ownPackage,
        )

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
echo "== Corriendo ./gradlew :blockade:assembleDebug (para confirmar que la Service tambien compila contra el SDK real de Android) =="
./gradlew :blockade:assembleDebug

echo ""
echo "== Estado en git =="
git add -A
git status --short

echo ""
echo "== Diff exacto (sin paginador) =="
git --no-pager diff --cached -- \
    "blockade/src/main/java/com/irrovicas/blockade/platform/enforcement" \
    "blockade/src/main/java/com/irrovicas/blockade/accessibility" \
    "blockade/src/test/java/com/irrovicas/blockade/platform/enforcement" \
    "blockade/src/test/java/com/irrovicas/blockade/accessibility"

cat << 'MSG'
============================================================
Fase 4, Paso 2 completado: enforcement conectado via BlockadeAccessibilityService.

Se crearon (paquete platform/enforcement):
  - BlockEnforcer.kt                  (interfaz)
  - GlobalActionPerformer.kt          (seam testeable sobre performGlobalAction)
  - BlockEnforcementActionResolver.kt (logica pura: LAUNCH/FULL -> enforce)
  - AndroidBlockEnforcer.kt           (implementacion: GLOBAL_ACTION_HOME)

Se creo (paquete accessibility):
  - AccessibilityEventFilter.kt       (logica pura de interpretacion
                                        de evento + auto-exclusion)

Se modifico:
  - accessibility/BlockadeAccessibilityService.kt
    Ya NO es un placeholder. Ahora observa politicas activas,
    resuelve el evento, consulta appContainer.policyEvaluator
    (motor YA EXISTENTE, no duplicado) y delega el enforcement.

Se agregaron tests unitarios (10 casos totales, logica pura,
sin Robolectric ni Mockito porque el proyecto no los tiene
configurados - se evito deliberadamente depender de ellos):
  - BlockEnforcementActionResolverTest.kt (5 casos)
  - AccessibilityEventFilterTest.kt (5 casos)

Decisiones propias (distintas al detalle literal de lo que planteo
ChatGPT, coherentes con lo que ya existia en el repo):
  - No se creo una interfaz Policy nueva ni un enforce(packageName,
    policy) simplificado: se conecto PolicyEvaluator/EnforcementDecision,
    que ya estaban implementados desde antes y ya seguian esa misma
    filosofia "motor decide que, Android decide como".
  - typeWindowContentChanged (el evento mas ruidoso, ya habilitado en
    el XML) se filtra y se descarta ANTES de tocar el motor de
    decision, para no evaluar politicas en cada cambio de contenido.
  - El enforcement solo actua si la decision incluye LAUNCH o FULL;
    una politica que solo silencia NOTIFICATION no saca al usuario
    de la app.

NO se toco (a proposito):
  - QuickBlockScreen.kt (sigue sin boton para habilitar accesibilidad)
  - AndroidManifest.xml / blockade_accessibility_service.xml
  - ForegroundAppProvider (Fase 4 Paso 1) - queda como mecanismo de
    consulta/respaldo, tal como pidio ChatGPT, no como señal primaria

Revisa arriba el resultado de ./gradlew :blockade:test y
./gradlew :blockade:assembleDebug. Si todo paso, commitea y sube:

  git commit -m "feat(blockade): implement AccessibilityService enforcement with BlockEnforcer"
  git push origin main

Importante para probarlo en un dispositivo real: el usuario todavia
tiene que habilitar el servicio manualmente en
Ajustes > Accesibilidad, porque no existe (a proposito, todavia) un
boton en la app que lleve alli. Eso es un paso de UI aparte.
============================================================
MSG
