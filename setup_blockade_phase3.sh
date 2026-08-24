#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_blockade_phase3.sh
#
# Fase 3 - Quick Block UI (vertical slice), segun el diseno de
# ChatGPT: DI manual con AppContainer, BlockadeApplication,
# RoomPolicyRepository como implementacion real, ViewModel +
# Compose para la pantalla de Quick Block, e InstalledAppsProvider
# basado en actividades lanzables (sin QUERY_ALL_PACKAGES).
#
# IMPORTANTE - verificacion previa contra el repo real (no se
# adivino nada, se corrigieron 2 problemas concretos del texto
# de ChatGPT antes de generar este script):
#
# 1) CreateQuickBlockUseCase, StopQuickBlockUseCase y
#    ObservePoliciesUseCase NO tienen "operator fun invoke()".
#    Su metodo real es .execute(...) (confirmado leyendo los
#    3 archivos y QuickBlockUseCaseTest.kt). El ViewModel que
#    dio ChatGPT los llamaba como funciones
#    (createQuickBlockUseCase(quickBlock), etc.) - eso no
#    compila contra tu codigo real. Se corrigio a
#    .execute(...) en los 3 sitios. ChatGPT mismo avisaba de
#    este riesgo ("si tus clases tienen metodos con nombres
#    distintos, no cambies la arquitectura: adapta las
#    llamadas").
#
# 2) QuickBlockScreen.kt necesitaba el import de BlockTarget y
#    la funcion targetLabel() que ChatGPT dio como nota aparte
#    ("anadelo al final del archivo") en vez de dejarlos fuera
#    del bloque de codigo principal. Ya estan integrados en el
#    archivo que este script escribe.
#
# El resto del codigo de ChatGPT (AppContainer, BlockadeApplication,
# InstalledApp(s)Provider, QuickBlockUiState, QuickBlockViewModelFactory)
# se verifico contra las firmas reales de RoomPolicyRepository,
# BlockadeDatabase, PolicyEvaluator, ConflictResolver y QuickBlock,
# y coincide sin cambios.
#
# NO se crea el test del ViewModel: ChatGPT decidio explicitamente
# diferirlo hasta normalizar las firmas reales de los use cases,
# asi que este script tampoco lo inventa.
#
# NO se corre :blockade:connectedDebugAndroidTest (necesita un
# emulador/dispositivo conectado, que Codespaces no trae por
# defecto). Eso queda pendiente para cuando haya uno disponible,
# igual que RoomPolicyRepositoryTest de la Fase 2.6.
# ============================================================

REPO_ROOT="$(pwd)"
BLOCKADE_DIR="$REPO_ROOT/blockade"
MAIN_DIR="$BLOCKADE_DIR/src/main/java/com/irrovicas/blockade"
MANIFEST_FILE="$BLOCKADE_DIR/src/main/AndroidManifest.xml"
BUILD_FILE="$BLOCKADE_DIR/build.gradle.kts"

echo "== Validando precondiciones =="

if [ ! -f "$BUILD_FILE" ]; then
  echo "ERROR: no se encontro blockade/build.gradle.kts."
  echo "       Corre este script desde la raiz del repo (PROYECTO/)."
  exit 1
fi

if [ ! -f "$MAIN_DIR/data/repository/RoomPolicyRepository.kt" ]; then
  echo "ERROR: no se encontro RoomPolicyRepository.kt."
  echo "       Este script asume que la Fase 2.6 (Room) ya esta aplicada."
  exit 1
fi

if [ ! -f "$MAIN_DIR/data/local/db/BlockadeDatabase.kt" ]; then
  echo "ERROR: no se encontro BlockadeDatabase.kt (Fase 2.6)."
  exit 1
fi

for uc in CreateQuickBlockUseCase StopQuickBlockUseCase ObservePoliciesUseCase; do
  UC_FILE="$MAIN_DIR/domain/usecase/$uc.kt"
  if [ ! -f "$UC_FILE" ]; then
    echo "ERROR: no se encontro $UC_FILE"
    exit 1
  fi
  if ! grep -q "fun execute(" "$UC_FILE"; then
    echo "ERROR: $uc no tiene un metodo execute(...) como se esperaba."
    echo "       El contrato cambio respecto a lo verificado - abortando"
    echo "       en vez de adivinar como llamarlo desde el ViewModel."
    exit 1
  fi
done

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "ERROR: no se encontro AndroidManifest.xml"
  exit 1
fi

echo "OK: Fase 2.6 (Room) presente, los 3 use cases tienen .execute(...), Manifest encontrado."

echo "== Creando estructura de carpetas de Fase 3 =="
mkdir -p "$MAIN_DIR/di"
mkdir -p "$MAIN_DIR/platform/apps"
mkdir -p "$MAIN_DIR/ui/quickblock"

echo "== Escribiendo BlockadeApplication.kt =="
cat > "$MAIN_DIR/BlockadeApplication.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade

import android.app.Application
import com.irrovicas.blockade.di.AppContainer

class BlockadeApplication : Application() {

    lateinit var appContainer: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()

        appContainer = AppContainer(this)
    }
}
KOTLIN_EOF

echo "== Escribiendo di/AppContainer.kt =="
cat > "$MAIN_DIR/di/AppContainer.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.di

import android.content.Context
import com.irrovicas.blockade.data.local.db.BlockadeDatabase
import com.irrovicas.blockade.data.repository.RoomPolicyRepository
import com.irrovicas.blockade.domain.engine.ConflictResolver
import com.irrovicas.blockade.domain.engine.PolicyEvaluator
import com.irrovicas.blockade.domain.repository.PolicyRepository
import com.irrovicas.blockade.domain.usecase.CreateQuickBlockUseCase
import com.irrovicas.blockade.domain.usecase.ObservePoliciesUseCase
import com.irrovicas.blockade.domain.usecase.StopQuickBlockUseCase
import com.irrovicas.blockade.platform.apps.AndroidInstalledAppsProvider
import com.irrovicas.blockade.platform.apps.InstalledAppsProvider

class AppContainer(
    context: Context,
) {
    private val database =
        BlockadeDatabase.getInstance(context)

    private val policyDao =
        database.policyDao()

    val policyRepository: PolicyRepository =
        RoomPolicyRepository(policyDao)

    val policyEvaluator =
        PolicyEvaluator()

    val conflictResolver =
        ConflictResolver()

    val createQuickBlock =
        CreateQuickBlockUseCase(policyRepository)

    val stopQuickBlock =
        StopQuickBlockUseCase(policyRepository)

    val observePolicies =
        ObservePoliciesUseCase(policyRepository)

    val installedAppsProvider: InstalledAppsProvider =
        AndroidInstalledAppsProvider(context)
}
KOTLIN_EOF

echo "== Escribiendo platform/apps/InstalledApp.kt =="
cat > "$MAIN_DIR/platform/apps/InstalledApp.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.platform.apps

data class InstalledApp(
    val packageName: String,
    val label: String,
)
KOTLIN_EOF

echo "== Escribiendo platform/apps/InstalledAppsProvider.kt =="
cat > "$MAIN_DIR/platform/apps/InstalledAppsProvider.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.platform.apps

interface InstalledAppsProvider {

    fun getLaunchableApps(): List<InstalledApp>
}
KOTLIN_EOF

echo "== Escribiendo platform/apps/AndroidInstalledAppsProvider.kt =="
cat > "$MAIN_DIR/platform/apps/AndroidInstalledAppsProvider.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.platform.apps

import android.content.Context
import android.content.Intent

class AndroidInstalledAppsProvider(
    private val context: Context,
) : InstalledAppsProvider {

    override fun getLaunchableApps(): List<InstalledApp> {
        val packageManager = context.packageManager

        val launcherIntent = Intent(
            Intent.ACTION_MAIN,
        ).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        return packageManager
            .queryIntentActivities(
                launcherIntent,
                0,
            )
            .asSequence()
            .mapNotNull { resolveInfo ->
                val packageName =
                    resolveInfo.activityInfo?.packageName
                        ?: return@mapNotNull null

                if (packageName == context.packageName) {
                    return@mapNotNull null
                }

                val label =
                    resolveInfo.loadLabel(packageManager)
                        ?.toString()
                        ?.trim()
                        .orEmpty()

                if (label.isBlank()) {
                    return@mapNotNull null
                }

                InstalledApp(
                    packageName = packageName,
                    label = label,
                )
            }
            .distinctBy(InstalledApp::packageName)
            .sortedBy {
                it.label.lowercase()
            }
            .toList()
    }
}
KOTLIN_EOF

echo "== Escribiendo ui/quickblock/QuickBlockUiState.kt =="
cat > "$MAIN_DIR/ui/quickblock/QuickBlockUiState.kt" << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo ui/quickblock/QuickBlockViewModel.kt (con .execute corregido) =="
cat > "$MAIN_DIR/ui/quickblock/QuickBlockViewModel.kt" << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo ui/quickblock/QuickBlockViewModelFactory.kt =="
cat > "$MAIN_DIR/ui/quickblock/QuickBlockViewModelFactory.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.ui.quickblock

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.irrovicas.blockade.di.AppContainer

class QuickBlockViewModelFactory(
    private val appContainer: AppContainer,
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(
        modelClass: Class<T>,
    ): T {
        require(
            modelClass.isAssignableFrom(
                QuickBlockViewModel::class.java,
            ),
        )

        return QuickBlockViewModel(
            installedAppsProvider =
                appContainer.installedAppsProvider,
            createQuickBlockUseCase =
                appContainer.createQuickBlock,
            stopQuickBlockUseCase =
                appContainer.stopQuickBlock,
            observePoliciesUseCase =
                appContainer.observePolicies,
        ) as T
    }
}
KOTLIN_EOF

echo "== Escribiendo ui/quickblock/QuickBlockScreen.kt (con targetLabel integrado) =="
cat > "$MAIN_DIR/ui/quickblock/QuickBlockScreen.kt" << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Reescribiendo MainActivity.kt (pierde el boton de Accesibilidad a proposito) =="
cat > "$MAIN_DIR/MainActivity.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.irrovicas.blockade.ui.quickblock.QuickBlockScreen

class MainActivity : ComponentActivity() {

    override fun onCreate(
        savedInstanceState: Bundle?,
    ) {
        super.onCreate(savedInstanceState)

        val appContainer =
            (application as BlockadeApplication)
                .appContainer

        setContent {
            MaterialTheme {
                Surface {
                    QuickBlockScreen(
                        appContainer = appContainer,
                    )
                }
            }
        }
    }
}
KOTLIN_EOF

echo "== Reescribiendo AndroidManifest.xml (agrega android:name=.BlockadeApplication) =="
cat > "$MANIFEST_FILE" << 'MANIFEST_EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions" xmlns:tools="http://schemas.android.com/tools" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <application android:name=".BlockadeApplication" android:theme="@style/Theme.IRROVICAS.Blockade" android:label="@string/app_name" android:allowBackup="false">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".accessibility.BlockadeAccessibilityService"
            android:exported="false"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/blockade_accessibility_service" />
        </service>
    </application>
</manifest>
MANIFEST_EOF

echo "== Reescribiendo blockade/build.gradle.kts (agrega dependencias de lifecycle-compose) =="
cat > "$BUILD_FILE" << 'GRADLE_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
}
android {
    namespace = "com.irrovicas.blockade"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.irrovicas.blockade"
        minSdk = 35
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}
kotlin { jvmToolchain(17) }
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.08.00")
    implementation(composeBom)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.10.0")
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    ksp("androidx.room:room-compiler:2.8.4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation(kotlin("test-junit"))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.room:room-testing:2.8.4")
}
GRADLE_EOF

echo "OK: todos los archivos de Fase 3 escritos."

echo ""
echo "== Deteniendo el daemon de Gradle antes de compilar (memoria limitada en Codespaces) =="
cd "$REPO_ROOT"
./gradlew --stop

echo ""
echo "== Corriendo ./gradlew :blockade:test =="
./gradlew :blockade:test

echo ""
echo "== Corriendo ./gradlew :blockade:assembleDebug =="
./gradlew :blockade:assembleDebug

echo ""
echo "== Estado en git =="
git add -A
git status --short

cat << 'MSG'

============================================================
Fase 3 (Quick Block UI) escrita y compilada.

Para commitear y subir:

  git commit -m "feat(blockade): Fase 3 - Quick Block UI (AppContainer, ViewModel, Compose screen)"
  git push origin main

Pendientes que quedaron explicitamente fuera de este script
(tal como los definio ChatGPT, no por omision):

  - QuickBlockViewModelTest.kt: ChatGPT prefirio normalizar
    primero las firmas reales de los use cases antes de
    escribir este test. Ya estan normalizadas (.execute()),
    asi que la proxima vez que hables con el puedes pedirselo
    directamente.
  - RoomPolicyRepositoryTest.kt (Fase 2.6) y cualquier prueba
    instrumentada de esta fase siguen pendientes de un
    emulador/dispositivo conectado via:
      ./gradlew :blockade:connectedDebugAndroidTest

Instagram/YouTube/Chrome todavia NO se bloquean de verdad -
eso es intencional, es la Fase 4 (enforcement).
============================================================
MSG
