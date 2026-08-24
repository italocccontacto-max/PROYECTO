package com.irrovicas.blockade.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Fila raíz de una BlockadePolicy persistida.
 *
 * No incluye createdAt/updatedAt: BlockadePolicy (dominio) no tiene
 * esos campos hoy, y esta fase no les inventa semántica que nadie pidió.
 * Si en una fase futura el dominio los incorpora, se añaden aquí en
 * el mismo cambio que los añada allá.
 */
@Entity(
    tableName = "blockade_policies",
)
data class PolicyEntity(
    @PrimaryKey
    val id: String,
    val name: String,
    val source: String,
    val enabled: Boolean,
    val paused: Boolean,
    val conditionMode: String,
    val strictness: String,
    val expiresAtEpochMillis: Long?,
)
