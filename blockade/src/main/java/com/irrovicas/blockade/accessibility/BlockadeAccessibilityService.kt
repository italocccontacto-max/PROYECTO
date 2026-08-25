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
