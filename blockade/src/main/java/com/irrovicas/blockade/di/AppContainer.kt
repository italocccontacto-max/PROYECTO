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
