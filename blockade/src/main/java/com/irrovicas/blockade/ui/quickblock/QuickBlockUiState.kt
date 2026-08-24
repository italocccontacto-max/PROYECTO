package com.irrovicas.blockade.ui.quickblock

import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.platform.apps.InstalledApp
import java.time.Instant

data class QuickBlockUiState(
    val installedApps: List<InstalledApp> = emptyList(),
    val selectedPackages: Set<String> = emptySet(),
    val policies: List<BlockadePolicy> = emptyList(),
    val duration: QuickBlockDuration = QuickBlockDuration.MINUTES_25,
    val isLoadingApps: Boolean = false,
    val isCreating: Boolean = false,
    val errorMessage: String? = null,
)

enum class QuickBlockDuration(
    val label: String,
    val minutes: Long?,
) {
    UNLIMITED(
        label = "Sin límite",
        minutes = null,
    ),

    MINUTES_25(
        label = "25 minutos",
        minutes = 25,
    ),

    HOUR_1(
        label = "1 hora",
        minutes = 60,
    );

    fun expiresAt(
        now: Instant,
    ): Instant? {
        return minutes?.let {
            now.plusSeconds(it * 60)
        }
    }
}
