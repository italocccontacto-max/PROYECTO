package com.irrovicas.blockade.ui.quickblock

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.QuickBlock
import com.irrovicas.blockade.domain.usecase.CreateQuickBlockUseCase
import com.irrovicas.blockade.domain.usecase.ObservePoliciesUseCase
import com.irrovicas.blockade.domain.usecase.StopQuickBlockUseCase
import com.irrovicas.blockade.platform.apps.InstalledApp
import com.irrovicas.blockade.platform.apps.InstalledAppsProvider
import java.time.Clock
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class QuickBlockViewModel(
    private val installedAppsProvider: InstalledAppsProvider,
    private val createQuickBlockUseCase: CreateQuickBlockUseCase,
    private val stopQuickBlockUseCase: StopQuickBlockUseCase,
    private val observePoliciesUseCase: ObservePoliciesUseCase,
    private val clock: Clock = Clock.systemUTC(),
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        QuickBlockUiState(),
    )

    val uiState: StateFlow<QuickBlockUiState> =
        _uiState.asStateFlow()

    init {
        observePoliciesUseCase.execute()
            .catch { error ->
                _uiState.update {
                    it.copy(
                        errorMessage =
                            error.message
                                ?: "No se pudieron cargar las políticas.",
                    )
                }
            }
            .let { flow ->
                viewModelScope.launch {
                    flow.collect { policies ->
                        _uiState.update {
                            it.copy(
                                policies = policies,
                                errorMessage = null,
                            )
                        }
                    }
                }
            }

        refreshApps()
    }

    fun refreshApps() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoadingApps = true,
                    errorMessage = null,
                )
            }

            runCatching {
                installedAppsProvider.getLaunchableApps()
            }.onSuccess { apps ->
                _uiState.update {
                    it.copy(
                        installedApps = apps,
                        isLoadingApps = false,
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        isLoadingApps = false,
                        errorMessage =
                            error.message
                                ?: "No se pudieron cargar las aplicaciones.",
                    )
                }
            }
        }
    }

    fun togglePackage(
        packageName: String,
    ) {
        _uiState.update { state ->
            val updatedSelection =
                if (packageName in state.selectedPackages) {
                    state.selectedPackages - packageName
                } else {
                    state.selectedPackages + packageName
                }

            state.copy(
                selectedPackages = updatedSelection,
            )
        }
    }

    fun selectDuration(
        duration: QuickBlockDuration,
    ) {
        _uiState.update {
            it.copy(duration = duration)
        }
    }

    fun createQuickBlock() {
        val state = uiState.value

        if (state.selectedPackages.isEmpty()) {
            _uiState.update {
                it.copy(
                    errorMessage =
                        "Selecciona al menos una aplicación.",
                )
            }
            return
        }

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isCreating = true,
                    errorMessage = null,
                )
            }

            val now = Instant.now(clock)

            val quickBlock = QuickBlock(
                id = UUID.randomUUID().toString(),
                enabled = true,
                startedAt = now,
                expiresAt = state.duration.expiresAt(now),
                targets = state.selectedPackages.map {
                    BlockTarget.Application(it)
                }.toSet(),
                actions = setOf(
                    BlockAction.LAUNCH,
                ),
            )

            runCatching {
                createQuickBlockUseCase.execute(quickBlock)
            }.onSuccess {
                _uiState.update {
                    it.copy(
                        isCreating = false,
                        selectedPackages = emptySet(),
                        errorMessage = null,
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        isCreating = false,
                        errorMessage =
                            error.message
                                ?: "No se pudo crear el Quick Block.",
                    )
                }
            }
        }
    }

    fun stopPolicy(
        policyId: String,
    ) {
        viewModelScope.launch {
            runCatching {
                stopQuickBlockUseCase.execute(policyId)
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        errorMessage =
                            error.message
                                ?: "No se pudo detener el Quick Block.",
                    )
                }
            }
        }
    }

    fun installedApp(
        packageName: String,
    ): InstalledApp? {
        return uiState.value.installedApps
            .firstOrNull {
                it.packageName == packageName
            }
    }
}
