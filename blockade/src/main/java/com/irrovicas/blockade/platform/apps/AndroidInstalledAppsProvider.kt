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
                        .toString()
                        .trim()

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
