package com.irrovicas.system

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { SystemApp() }
    }
}

private data class SystemSection(val title: String, val subtitle: String)

@androidx.compose.runtime.Composable
private fun SystemApp() {
    val sections = listOf(
        SystemSection("NÚCLEO", "Principios · Identidad · Antiidentidad"),
        SystemSection("ORIENTACIÓN", "Rumbo · Plan"),
        SystemSection("OPERACIÓN", "Decisiones · Protocolos · Ejecución"),
        SystemSection("MEMORIA Y APRENDIZAJE", "Archivo · Conocimiento")
    )
    var selected by remember { mutableIntStateOf(0) }
    val section = sections[selected]

    MaterialTheme {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    sections.forEachIndexed { index, item ->
                        NavigationBarItem(
                            selected = selected == index,
                            onClick = { selected = index },
                            icon = { Text((index + 1).toString()) },
                            label = { Text(item.title.take(10)) }
                        )
                    }
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("IRROVICAS SYSTEM", style = MaterialTheme.typography.headlineMedium)
                Text(section.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 24.dp))
                Text(section.subtitle, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}
