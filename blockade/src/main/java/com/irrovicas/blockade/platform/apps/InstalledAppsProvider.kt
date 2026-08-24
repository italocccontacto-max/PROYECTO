package com.irrovicas.blockade.platform.apps

interface InstalledAppsProvider {

    fun getLaunchableApps(): List<InstalledApp>
}
