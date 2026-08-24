package com.irrovicas.blockade.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "blockade_actions",
    primaryKeys = [
        "policyId",
        "action",
    ],
    foreignKeys = [
        ForeignKey(
            entity = PolicyEntity::class,
            parentColumns = ["id"],
            childColumns = ["policyId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index("policyId"),
    ],
)
data class ActionEntity(
    val policyId: String,
    val action: String,
)
