package com.irrovicas.blockade.domain.engine

import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.StrictnessLevel

/**
 * Resuelve conflictos entre varias políticas que afectan
 * al mismo objetivo.
 *
 * Principio:
 * la condición más estricta siempre gana.
 */
class ConflictResolver {

    fun resolve(
        policies: Collection<BlockadePolicy>,
    ): BlockadePolicy? {
        if (policies.isEmpty()) {
            return null
        }

        return policies
            .filter { it.enabled && !it.paused }
            .maxWithOrNull(
                compareBy<BlockadePolicy> {
                    it.strictness.rank()
                }.thenBy {
                    actionStrictness(it.actions)
                }.thenBy {
                    it.conditions.size
                },
            )
    }

    fun resolveActions(
        policies: Collection<BlockadePolicy>,
    ): Set<BlockAction> {
        return policies
            .filter { it.enabled && !it.paused }
            .flatMap { it.actions }
            .toSet()
    }

    fun conflicting(
        first: BlockadePolicy,
        second: BlockadePolicy,
    ): Boolean {
        return first.targets.any { firstTarget ->
            second.targets.any { secondTarget ->
                targetsOverlap(firstTarget, secondTarget)
            }
        }
    }

    private fun targetsOverlap(
        first: BlockTarget,
        second: BlockTarget,
    ): Boolean {
        return when {
            first is BlockTarget.Application &&
                second is BlockTarget.Application ->
                first.packageName == second.packageName

            first is BlockTarget.WebDomain &&
                second is BlockTarget.WebDomain ->
                normalizeDomain(first.domain) ==
                    normalizeDomain(second.domain)

            first is BlockTarget.Keyword &&
                second is BlockTarget.Keyword ->
                first.value.equals(
                    second.value,
                    ignoreCase = true,
                )

            first is BlockTarget.AppContent &&
                second is BlockTarget.AppContent ->
                first.packageName == second.packageName &&
                    first.contentType == second.contentType

            else -> false
        }
    }

    private fun StrictnessLevel.rank(): Int {
        return when (this) {
            StrictnessLevel.NORMAL -> 1
            StrictnessLevel.STRICT -> 2
            StrictnessLevel.ABSOLUTE -> 3
        }
    }

    private fun actionStrictness(
        actions: Set<BlockAction>,
    ): Int {
        return when {
            BlockAction.FULL in actions -> 3
            BlockAction.LAUNCH in actions &&
                BlockAction.NOTIFICATION in actions -> 2

            BlockAction.LAUNCH in actions ||
                BlockAction.NOTIFICATION in actions -> 1

            else -> 0
        }
    }

    private fun normalizeDomain(domain: String): String {
        return domain
            .trim()
            .lowercase()
            .removePrefix("https://")
            .removePrefix("http://")
            .removePrefix("www.")
            .trimEnd('/')
    }
}
