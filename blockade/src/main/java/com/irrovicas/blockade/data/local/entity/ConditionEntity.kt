package com.irrovicas.blockade.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "blockade_conditions",
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
data class ConditionEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val policyId: String,
    val type: String,

    val startTime: String?,
    val endTime: String?,
    val daysOfWeek: String?,

    val limitMinutes: Long?,
    val usageScope: String?,

    val maximumLaunches: Int?,

    val latitude: Double?,
    val longitude: Double?,
    val radiusMeters: Float?,
    val locationMode: String?,

    val ssid: String?,
)
