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
