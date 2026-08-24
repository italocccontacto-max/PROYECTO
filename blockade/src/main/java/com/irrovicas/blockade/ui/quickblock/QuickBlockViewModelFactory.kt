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
