package com.irrovicas.blockade.data.local.entity

import androidx.room.Embedded
import androidx.room.Relation

data class PolicyWithRelations(
    @Embedded
    val policy: PolicyEntity,

    @Relation(
        parentColumn = "id",
        entityColumn = "policyId",
    )
    val targets: List<TargetEntity>,

    @Relation(
        parentColumn = "id",
        entityColumn = "policyId",
    )
    val conditions: List<ConditionEntity>,

    @Relation(
        parentColumn = "id",
        entityColumn = "policyId",
    )
    val actions: List<ActionEntity>,
)
