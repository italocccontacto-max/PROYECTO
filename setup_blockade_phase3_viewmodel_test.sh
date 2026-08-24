#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_blockade_phase3_viewmodel_test.sh
#
# QuickBlockViewModelTest.kt - la pieza que ChatGPT dejo pendiente
# a proposito en Fase 3 hasta normalizar las firmas reales de los
# use cases. Ya estan normalizadas (.execute(...), confirmado en
# main, commit 76d98f2), asi que este script la escribe.
#
# VERIFICADO CONTRA EL REPO REAL (no se adivino nada):
#
# 1) InMemoryPolicyRepository ya existe (domain/repository/), y ya
#    la usa QuickBlockUseCaseTest.kt de una fase anterior para
#    probar los use cases contra una implementacion real de
#    PolicyRepository sin Room. Este script reutiliza esa misma
#    clase para el ViewModel en vez de traer una libreria de
#    mocking: se construye el ViewModel con los 3 use cases reales
#    apuntando a un InMemoryPolicyRepository, asi los tests
#    verifican comportamiento real (se guarda la politica, se
#    deshabilita, se refleja en el flujo observado) en vez de solo
#    verificar llamadas simuladas. Mismo estilo que ya tiene el repo.
#
# 2) El ViewModel usa viewModelScope, que por dentro corre en
#    Dispatchers.Main.immediate. El modulo blockade NO tenia
#    kotlinx-coroutines-test como dependencia de test (solo
#    kotlin("test-junit")). Este script agrega UNA linea a
#    blockade/build.gradle.kts:
#      testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.1")
#    (misma version que kotlinx-coroutines-android, que ya esta en
#    1.10.1). Con eso alcanza para Dispatchers.setMain(UnconfinedTestDispatcher())
#    - no hace falta Robolectric: ViewModel y viewModelScope son
#    JVM puro, no tocan Android framework.
#
# 3) NO se toca el warning de la safe call en
#    AndroidInstalledAppsProvider.kt:36. ChatGPT pidio explicitamente
#    dejarlo para un commit aparte.
#
# 4) NO se crea nada de Fase 4 (enforcement / UsageStatsManager).
#    Este script es solo el test que quedo pendiente antes de esa fase.
# ============================================================

REPO_ROOT="$(pwd)"
BLOCKADE_DIR="$REPO_ROOT/blockade"
MAIN_DIR="$BLOCKADE_DIR/src/main/java/com/irrovicas/blockade"
TEST_DIR="$BLOCKADE_DIR/src/test/java/com/irrovicas/blockade"
BUILD_FILE="$BLOCKADE_DIR/build.gradle.kts"

echo "== Validando precondiciones =="

if [ ! -f "$BUILD_FILE" ]; then
  echo "ERROR: no se encontro blockade/build.gradle.kts."
  echo "       Corre este script desde la raiz del repo (PROYECTO/)."
  exit 1
fi

if [ ! -f "$MAIN_DIR/ui/quickblock/QuickBlockViewModel.kt" ]; then
  echo "ERROR: no se encontro QuickBlockViewModel.kt."
  echo "       Este script asume que la Fase 3 ya esta aplicada (main en 76d98f2 o posterior)."
  exit 1
fi

if [ ! -f "$MAIN_DIR/domain/repository/InMemoryPolicyRepository.kt" ]; then
  echo "ERROR: no se encontro InMemoryPolicyRepository.kt."
  echo "       Este script lo reutiliza tal cual, no lo crea."
  exit 1
fi

if ! grep -q "fun execute(quickBlock: QuickBlock)" "$MAIN_DIR/domain/usecase/CreateQuickBlockUseCase.kt"; then
  echo "ERROR: la firma de CreateQuickBlockUseCase.execute cambio respecto a lo verificado."
  echo "       Abortando en vez de adivinar como llamarla."
  exit 1
fi

if ! grep -q "fun execute(policyId: String)" "$MAIN_DIR/domain/usecase/StopQuickBlockUseCase.kt"; then
  echo "ERROR: la firma de StopQuickBlockUseCase.execute cambio respecto a lo verificado."
  exit 1
fi

echo "OK: Fase 3 presente, InMemoryPolicyRepository disponible, firmas de los 3 use cases verificadas."

echo "== Creando estructura de carpetas de test =="
mkdir -p "$TEST_DIR/ui/quickblock"

echo "== Escribiendo ui/quickblock/QuickBlockViewModelTest.kt =="
cat > "$TEST_DIR/ui/quickblock/QuickBlockViewModelTest.kt" << 'KOTLIN_EOF'
@file:OptIn(ExperimentalCoroutinesApi::class)

package com.irrovicas.blockade.ui.quickblock

import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.QuickBlock
import com.irrovicas.blockade.domain.repository.InMemoryPolicyRepository
import com.irrovicas.blockade.domain.usecase.CreateQuickBlockUseCase
import com.irrovicas.blockade.domain.usecase.ObservePoliciesUseCase
import com.irrovicas.blockade.domain.usecase.StopQuickBlockUseCase
import com.irrovicas.blockade.platform.apps.InstalledApp
import com.irrovicas.blockade.platform.apps.InstalledAppsProvider
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain

/**
 * Cobertura de QuickBlockViewModel.
 *
 * No usa ninguna libreria de mocking: construye el ViewModel con
 * los 3 use cases reales apoyados en InMemoryPolicyRepository (la
 * misma implementacion en memoria que ya usa QuickBlockUseCaseTest),
 * asi que los tests verifican comportamiento real de punta a punta
 * (UI -> UseCase -> Repository -> flujo observado) en vez de solo
 * verificar llamadas simuladas.
 */
class QuickBlockViewModelTest {

    private val mainDispatcher = UnconfinedTestDispatcher()

    private val fixedInstant = Instant.parse("2026-08-23T15:00:00Z")
    private val fixedClock = Clock.fixed(fixedInstant, ZoneOffset.UTC)

    private val instagram = InstalledApp(
        packageName = "com.instagram.android",
        label = "Instagram",
    )

    private val youtube = InstalledApp(
        packageName = "com.google.android.youtube",
        label = "YouTube",
    )

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(mainDispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun buildViewModel(
        repository: InMemoryPolicyRepository = InMemoryPolicyRepository(),
        installedAppsProvider: InstalledAppsProvider = FakeInstalledAppsProvider(
            apps = listOf(instagram, youtube),
        ),
    ): Pair<QuickBlockViewModel, InMemoryPolicyRepository> {
        val viewModel = QuickBlockViewModel(
            installedAppsProvider = installedAppsProvider,
            createQuickBlockUseCase = CreateQuickBlockUseCase(repository),
            stopQuickBlockUseCase = StopQuickBlockUseCase(repository),
            observePoliciesUseCase = ObservePoliciesUseCase(repository),
            clock = fixedClock,
        )

        return viewModel to repository
    }

    @Test
    fun `initial state loads installed apps`() = runTest {
        val (viewModel, _) = buildViewModel()

        val state = viewModel.uiState.value

        assertEquals(listOf(instagram, youtube), state.installedApps)
        assertFalse(state.isLoadingApps)
        assertNull(state.errorMessage)
    }

    @Test
    fun `initial state observes policies that already existed`() = runTest {
        val repository = InMemoryPolicyRepository()
        val createUseCase = CreateQuickBlockUseCase(repository)

        val existing = createUseCase.execute(
            QuickBlock(
                id = "quick-existing",
                startedAt = fixedInstant,
                expiresAt = null,
                targets = setOf(BlockTarget.Application(instagram.packageName)),
            ),
        )

        val (viewModel, _) = buildViewModel(repository = repository)

        val policies = viewModel.uiState.value.policies

        assertEquals(1, policies.size)
        assertEquals(existing.id, policies.first().id)
    }

    @Test
    fun `createQuickBlock with no selection sets error and creates nothing`() = runTest {
        val (viewModel, repository) = buildViewModel()

        viewModel.createQuickBlock()

        val state = viewModel.uiState.value

        assertEquals("Selecciona al menos una aplicación.", state.errorMessage)
        assertFalse(state.isCreating)
        assertTrue(repository.observePolicies().first().isEmpty())
    }

    @Test
    fun `createQuickBlock with selection persists policy and updates state`() = runTest {
        val (viewModel, repository) = buildViewModel()

        viewModel.togglePackage(instagram.packageName)
        viewModel.selectDuration(QuickBlockDuration.HOUR_1)
        viewModel.createQuickBlock()

        val state = viewModel.uiState.value

        assertTrue(state.selectedPackages.isEmpty())
        assertFalse(state.isCreating)
        assertNull(state.errorMessage)
        assertEquals(1, state.policies.size)

        val saved = repository.observePolicies().first().single()

        assertEquals(
            setOf(BlockTarget.Application(instagram.packageName)),
            saved.targets,
        )
        assertEquals(fixedInstant.plusSeconds(3600), saved.expiresAt)
    }

    @Test
    fun `stopPolicy disables the target policy`() = runTest {
        val repository = InMemoryPolicyRepository()
        val createUseCase = CreateQuickBlockUseCase(repository)

        val created = createUseCase.execute(
            QuickBlock(
                id = "quick-to-stop",
                startedAt = fixedInstant,
                expiresAt = null,
                targets = setOf(BlockTarget.Application(youtube.packageName)),
            ),
        )

        val (viewModel, _) = buildViewModel(repository = repository)

        viewModel.stopPolicy(created.id)

        val stored = repository.getPolicy(created.id)
        assertEquals(false, stored?.enabled)

        val stateAfterStop = viewModel.uiState.value.policies.first { it.id == created.id }
        assertFalse(stateAfterStop.enabled)
    }

    @Test
    fun `togglePackage adds and removes a package from selection`() = runTest {
        val (viewModel, _) = buildViewModel()

        viewModel.togglePackage(instagram.packageName)
        assertEquals(setOf(instagram.packageName), viewModel.uiState.value.selectedPackages)

        viewModel.togglePackage(instagram.packageName)
        assertTrue(viewModel.uiState.value.selectedPackages.isEmpty())
    }

    @Test
    fun `selectDuration updates the selected duration`() = runTest {
        val (viewModel, _) = buildViewModel()

        assertEquals(QuickBlockDuration.MINUTES_25, viewModel.uiState.value.duration)

        viewModel.selectDuration(QuickBlockDuration.UNLIMITED)

        assertEquals(QuickBlockDuration.UNLIMITED, viewModel.uiState.value.duration)
    }

    @Test
    fun `installedApp returns the matching installed app`() = runTest {
        val (viewModel, _) = buildViewModel()

        assertEquals(instagram, viewModel.installedApp(instagram.packageName))
        assertNull(viewModel.installedApp("com.not.installed"))
    }

    @Test
    fun `refreshApps surfaces provider failure as an error message`() = runTest {
        val failure = IllegalStateException("no se pudo leer la lista de apps")

        val (viewModel, _) = buildViewModel(
            installedAppsProvider = FakeInstalledAppsProvider(error = failure),
        )

        val state = viewModel.uiState.value

        assertEquals(failure.message, state.errorMessage)
        assertFalse(state.isLoadingApps)
        assertTrue(state.installedApps.isEmpty())
    }
}

private class FakeInstalledAppsProvider(
    private val apps: List<InstalledApp> = emptyList(),
    private val error: Throwable? = null,
) : InstalledAppsProvider {

    override fun getLaunchableApps(): List<InstalledApp> {
        error?.let { throw it }
        return apps
    }
}
KOTLIN_EOF

echo "== Agregando kotlinx-coroutines-test a blockade/build.gradle.kts (si falta) =="
if grep -q "kotlinx-coroutines-test" "$BUILD_FILE"; then
  echo "   Ya estaba presente, no se toca."
else
  sed -i '/testImplementation(kotlin("test-junit"))/a\    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.1")' "$BUILD_FILE"
  echo "   Agregada."
fi

echo "OK: archivo de test escrito, dependencia de test agregada."

echo ""
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

cat << 'MSG'

============================================================
QuickBlockViewModelTest.kt escrito y corrido (8 tests):

  - initial state loads installed apps
  - initial state observes policies that already existed
  - createQuickBlock con seleccion vacia -> error, no crea nada
  - createQuickBlock con seleccion -> persiste, limpia seleccion
  - stopPolicy deshabilita la politica (repo + estado observado)
  - togglePackage agrega/quita de la seleccion
  - selectDuration actualiza la duracion
  - installedApp devuelve la app correcta / null si no existe
  - refreshApps refleja error del provider como errorMessage

Para commitear y subir:

  git commit -m "test(blockade): cobertura de QuickBlockViewModel (Fase 3)"
  git push origin main

Pendientes, tal como los dejo ChatGPT explicitamente:

  - El warning de "safe call innecesaria" en
    AndroidInstalledAppsProvider.kt:36 sigue sin tocar - dijo
    que lo prefiere en un commit aparte.
  - RoomPolicyRepositoryTest.kt y los instrumented tests de esta
    fase siguen sin correr por falta de emulador/dispositivo.
  - Fase 4 (enforcement con UsageStatsManager) sigue sin empezar.

Si ./gradlew :blockade:test fallo, pegame el output completo antes
de escribirle a ChatGPT.
============================================================
MSG
