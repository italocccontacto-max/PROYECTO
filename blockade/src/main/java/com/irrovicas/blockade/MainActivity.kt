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
