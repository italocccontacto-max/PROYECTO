package com.irrovicas.blockade.ui.quickblock

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.irrovicas.blockade.di.AppContainer
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.platform.apps.InstalledApp

@Composable
fun QuickBlockScreen(
    appContainer: AppContainer,
    modifier: Modifier = Modifier,
) {
    val viewModel: QuickBlockViewModel = viewModel(
        factory = QuickBlockViewModelFactory(
            appContainer,
        ),
    )

    val state by viewModel.uiState
        .collectAsStateWithLifecycle()

    QuickBlockContent(
        state = state,
        onRefreshApps = viewModel::refreshApps,
        onTogglePackage = viewModel::togglePackage,
        onSelectDuration = viewModel::selectDuration,
        onCreateQuickBlock = viewModel::createQuickBlock,
        onStopPolicy = viewModel::stopPolicy,
        modifier = modifier,
    )
}

@Composable
private fun QuickBlockContent(
    state: QuickBlockUiState,
    onRefreshApps: () -> Unit,
    onTogglePackage: (String) -> Unit,
    onSelectDuration: (QuickBlockDuration) -> Unit,
    onCreateQuickBlock: () -> Unit,
    onStopPolicy: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier,
    ) { paddingValues ->

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Spacer(
                    modifier = Modifier.height(12.dp),
                )

                Text(
                    text = "IRROVICAS BLOCKADE",
                    style = MaterialTheme.typography.headlineSmall,
                )

                Text(
                    text = "Quick Block",
                    style = MaterialTheme.typography.titleLarge,
                )
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement =
                        Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Aplicaciones",
                        style = MaterialTheme.typography.titleMedium,
                    )

                    OutlinedButton(
                        onClick = onRefreshApps,
                    ) {
                        Text("Actualizar")
                    }
                }
            }

            if (state.isLoadingApps) {
                item {
                    Text("Cargando aplicaciones…")
                }
            }

            items(
                items = state.installedApps,
                key = InstalledApp::packageName,
            ) { app ->

                AppSelectionRow(
                    app = app,
                    selected =
                        app.packageName in state.selectedPackages,
                    onToggle = {
                        onTogglePackage(app.packageName)
                    },
                )
            }

            item {
                Text(
                    text = "Duración",
                    style = MaterialTheme.typography.titleMedium,
                )
            }

            items(
                items = QuickBlockDuration.entries,
                key = QuickBlockDuration::name,
            ) { duration ->

                Row(
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    RadioButton(
                        selected =
                            state.duration == duration,
                        onClick = {
                            onSelectDuration(duration)
                        },
                    )

                    Text(
                        text = duration.label,
                        modifier = Modifier.padding(
                            top = 12.dp,
                        ),
                    )
                }
            }

            item {
                Button(
                    onClick = onCreateQuickBlock,
                    enabled =
                        state.selectedPackages.isNotEmpty() &&
                            !state.isCreating,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text =
                            if (state.isCreating) {
                                "Iniciando…"
                            } else {
                                "INICIAR QUICK BLOCK"
                            },
                    )
                }
            }

            if (state.errorMessage != null) {
                item {
                    Text(
                        text = state.errorMessage,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            item {
                Spacer(
                    modifier = Modifier.height(8.dp),
                )

                HorizontalDivider()

                Spacer(
                    modifier = Modifier.height(8.dp),
                )

                Text(
                    text = "Políticas",
                    style = MaterialTheme.typography.titleLarge,
                )
            }

            if (state.policies.isEmpty()) {
                item {
                    Text(
                        text = "No hay Quick Blocks guardados.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            items(
                items = state.policies,
                key = BlockadePolicy::id,
            ) { policy ->

                PolicyCard(
                    policy = policy,
                    onStop = {
                        onStopPolicy(policy.id)
                    },
                )
            }

            item {
                Spacer(
                    modifier = Modifier.height(24.dp),
                )
            }
        }
    }
}

@Composable
private fun AppSelectionRow(
    app: InstalledApp,
    selected: Boolean,
    onToggle: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        onClick = onToggle,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement =
                Arrangement.SpaceBetween,
        ) {
            Column(
                modifier = Modifier.weight(1f),
            ) {
                Text(
                    text = app.label,
                    style = MaterialTheme.typography.bodyLarge,
                )

                Text(
                    text = app.packageName,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            FilterChip(
                selected = selected,
                onClick = onToggle,
                label = {
                    Text(
                        if (selected) {
                            "Seleccionada"
                        } else {
                            "Seleccionar"
                        },
                    )
                },
            )
        }
    }
}

@Composable
private fun PolicyCard(
    policy: BlockadePolicy,
    onStop: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = policy.name,
                style = MaterialTheme.typography.titleMedium,
            )

            Text(
                text =
                    if (policy.enabled) {
                        "Activa"
                    } else {
                        "Detenida"
                    },
            )

            Text(
                text =
                    policy.targets.joinToString {
                        targetLabel(it)
                    },
                style = MaterialTheme.typography.bodyMedium,
            )

            if (policy.expiresAt != null) {
                Text(
                    text =
                        "Vence: ${policy.expiresAt}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            if (policy.enabled) {
                OutlinedButton(
                    onClick = onStop,
                ) {
                    Text("Detener")
                }
            }
        }
    }
}

private fun targetLabel(
    target: BlockTarget,
): String {
    return when (target) {
        is BlockTarget.Application ->
            target.packageName

        is BlockTarget.WebDomain ->
            target.domain

        is BlockTarget.Keyword ->
            "Palabra: ${target.value}"

        is BlockTarget.AppContent ->
            "${target.packageName} · ${target.contentType}"
    }
}
