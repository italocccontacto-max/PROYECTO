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
