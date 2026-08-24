#!/usr/bin/env bash
set -e

echo "== Validando precondiciones =="

require_file() {
  if [ ! -f "$1" ]; then
    echo "ABORTA: no se encontró $1"
    exit 1
  fi
}

require_grep() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -q "$pattern" "$file"; then
    echo "ABORTA: $file no contiene $label"
    echo "        (el dominio cambió desde que se armó este script; pega la salida de este error, no lo fuerces)"
    exit 1
  fi
}

require_file "settings.gradle.kts"
require_file "build.gradle.kts"
require_file "gradlew"
require_file "blockade/build.gradle.kts"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockadePolicy.kt"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockCondition.kt"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockTarget.kt"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockAction.kt"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/model/Schedule.kt"
require_file "blockade/src/main/java/com/irrovicas/blockade/domain/repository/PolicyRepository.kt"

require_grep "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockadePolicy.kt" \
  "data class BlockadePolicy" "la data class BlockadePolicy"
require_grep "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockCondition.kt" \
  "sealed interface BlockCondition" "sealed interface BlockCondition"
require_grep "blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockTarget.kt" \
  "sealed interface BlockTarget" "sealed interface BlockTarget"
require_grep "blockade/src/main/java/com/irrovicas/blockade/domain/model/Schedule.kt" \
  "enum class ConditionMode" "enum class ConditionMode"
require_grep "blockade/src/main/java/com/irrovicas/blockade/domain/repository/PolicyRepository.kt" \
  "interface PolicyRepository" "la interface PolicyRepository"

policy_repo_methods=$(grep -c "fun " blockade/src/main/java/com/irrovicas/blockade/domain/repository/PolicyRepository.kt)
if [ "$policy_repo_methods" != "6" ]; then
  echo "ABORTA: PolicyRepository ya no tiene 6 métodos (tiene $policy_repo_methods)."
  echo "        RoomPolicyRepository fue armado contra los 6 originales; revisa qué cambió."
  exit 1
fi

if grep -q "createdAt\|updatedAt" blockade/src/main/java/com/irrovicas/blockade/domain/model/BlockadePolicy.kt; then
  echo "ABORTA: BlockadePolicy ahora SÍ tiene createdAt/updatedAt."
  echo "        Este script asume que no existen (por eso PolicyEntity no los persiste)."
  echo "        Si los agregaste a propósito, este script quedó desactualizado: avísame y lo ajusto."
  exit 1
fi

echo "OK: build.gradle.kts, gradlew, dominio (BlockadePolicy/BlockCondition/BlockTarget/ConditionMode) y PolicyRepository (6 métodos) verificados."
echo "OK: confirmado que BlockadePolicy sigue sin createdAt/updatedAt (por eso PolicyEntity tampoco los tiene)."

echo "== Creando estructura de directorios =="
mkdir -p blockade/src/main/java/com/irrovicas/blockade/data/local/entity
mkdir -p blockade/src/main/java/com/irrovicas/blockade/data/local/dao
mkdir -p blockade/src/main/java/com/irrovicas/blockade/data/local/db
mkdir -p blockade/src/main/java/com/irrovicas/blockade/data/local/mapper
mkdir -p blockade/src/main/java/com/irrovicas/blockade/data/repository
mkdir -p blockade/src/test/java/com/irrovicas/blockade/data/local
mkdir -p blockade/src/androidTest/java/com/irrovicas/blockade/data/repository
echo "OK: directorios creados."

echo "== Reescribiendo build.gradle.kts (root): agrega el plugin KSP =="
cat > build.gradle.kts << 'KOTLIN_EOF'
plugins {
    id("com.android.application") version "9.3.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21" apply false
    id("com.google.devtools.ksp") version "2.3.9" apply false
}

buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.21")
    }
}
KOTLIN_EOF
echo "OK: build.gradle.kts (root) reescrito."

echo "== Reescribiendo blockade/build.gradle.kts: agrega KSP, Room y dependencias de test instrumentado =="
cat > blockade/build.gradle.kts << 'KOTLIN_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
}
android {
    namespace = "com.irrovicas.blockade"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.irrovicas.blockade"
        minSdk = 35
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}
kotlin { jvmToolchain(17) }
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.08.00")
    implementation(composeBom)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    ksp("androidx.room:room-compiler:2.8.4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation(kotlin("test-junit"))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.room:room-testing:2.8.4")
}
KOTLIN_EOF
echo "OK: blockade/build.gradle.kts reescrito. Nota: agregué 'testInstrumentationRunner', que ChatGPT no puso -- sin eso connectedDebugAndroidTest no encuentra el runner."

echo "== Escribiendo PolicyEntity.kt (sin createdAt/updatedAt: no existen en el dominio) =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/entity/PolicyEntity.kt << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo TargetEntity.kt =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/entity/TargetEntity.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "blockade_targets",
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
data class TargetEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val policyId: String,
    val type: String,
    val value: String,
    val matchingMode: String?,
    val contentType: String?,
)
KOTLIN_EOF

echo "== Escribiendo ConditionEntity.kt =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/entity/ConditionEntity.kt << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo ActionEntity.kt =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/entity/ActionEntity.kt << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo PolicyWithRelations.kt =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/entity/PolicyWithRelations.kt << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo "== Escribiendo PolicyDao.kt (setEnabled/setPaused/observePolicies sin updatedAtEpochMillis) =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/dao/PolicyDao.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.irrovicas.blockade.data.local.entity.ActionEntity
import com.irrovicas.blockade.data.local.entity.ConditionEntity
import com.irrovicas.blockade.data.local.entity.PolicyEntity
import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.entity.TargetEntity
import kotlinx.coroutines.flow.Flow

@Dao
abstract class PolicyDao {

    @Transaction
    @Query(
        """
        SELECT * 
        FROM blockade_policies
        ORDER BY id ASC
        """,
    )
    abstract fun observePolicies(): Flow<List<PolicyWithRelations>>

    @Transaction
    @Query(
        """
        SELECT *
        FROM blockade_policies
        WHERE id = :id
        LIMIT 1
        """,
    )
    abstract suspend fun getPolicy(
        id: String,
    ): PolicyWithRelations?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertPolicy(
        policy: PolicyEntity,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertTargets(
        targets: List<TargetEntity>,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertConditions(
        conditions: List<ConditionEntity>,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertActions(
        actions: List<ActionEntity>,
    )

    @Query(
        "DELETE FROM blockade_targets WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteTargets(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_conditions WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteConditions(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_actions WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteActions(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_policies WHERE id = :policyId",
    )
    protected abstract suspend fun deletePolicy(
        policyId: String,
    )

    @Transaction
    open suspend fun replacePolicy(
        policy: PolicyEntity,
        targets: List<TargetEntity>,
        conditions: List<ConditionEntity>,
        actions: List<ActionEntity>,
    ) {
        deleteTargets(policy.id)
        deleteConditions(policy.id)
        deleteActions(policy.id)

        insertPolicy(policy)
        insertTargets(targets)
        insertConditions(conditions)
        insertActions(actions)
    }

    @Transaction
    open suspend fun deletePolicyAndChildren(
        policyId: String,
    ) {
        deleteTargets(policyId)
        deleteConditions(policyId)
        deleteActions(policyId)
        deletePolicy(policyId)
    }

    @Query(
        """
        UPDATE blockade_policies
        SET enabled = :enabled
        WHERE id = :id
        """,
    )
    abstract suspend fun setEnabled(
        id: String,
        enabled: Boolean,
    )

    @Query(
        """
        UPDATE blockade_policies
        SET paused = :paused
        WHERE id = :id
        """,
    )
    abstract suspend fun setPaused(
        id: String,
        paused: Boolean,
    )
}
KOTLIN_EOF

echo "== Escribiendo BlockadeDatabase.kt =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/db/BlockadeDatabase.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.local.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.irrovicas.blockade.data.local.dao.PolicyDao
import com.irrovicas.blockade.data.local.entity.ActionEntity
import com.irrovicas.blockade.data.local.entity.ConditionEntity
import com.irrovicas.blockade.data.local.entity.PolicyEntity
import com.irrovicas.blockade.data.local.entity.TargetEntity

@Database(
    entities = [
        PolicyEntity::class,
        TargetEntity::class,
        ConditionEntity::class,
        ActionEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class BlockadeDatabase : RoomDatabase() {

    abstract fun policyDao(): PolicyDao

    companion object {

        private const val DATABASE_NAME = "blockade.db"

        @Volatile
        private var INSTANCE: BlockadeDatabase? = null

        fun getInstance(
            context: Context,
        ): BlockadeDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    BlockadeDatabase::class.java,
                    DATABASE_NAME,
                ).build().also { database ->
                    INSTANCE = database
                }
            }
        }
    }
}
KOTLIN_EOF

echo "== Escribiendo PolicyEntityMapper.kt (sin createdAt/updatedAt en ninguna dirección) =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/local/mapper/PolicyEntityMapper.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.local.mapper

import com.irrovicas.blockade.data.local.entity.ActionEntity
import com.irrovicas.blockade.data.local.entity.ConditionEntity
import com.irrovicas.blockade.data.local.entity.PolicyEntity
import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.entity.TargetEntity
import com.irrovicas.blockade.domain.model.AppContentType
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockCondition
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import com.irrovicas.blockade.domain.model.KeywordMatchingMode
import com.irrovicas.blockade.domain.model.LocationMode
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import com.irrovicas.blockade.domain.model.UsageScope
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime

object PolicyEntityMapper {

    fun toEntities(
        policy: BlockadePolicy,
    ): PersistedPolicy {
        val policyEntity = PolicyEntity(
            id = policy.id,
            name = policy.name,
            source = policy.source.name,
            enabled = policy.enabled,
            paused = policy.paused,
            conditionMode = policy.conditionMode.name,
            strictness = policy.strictness.name,
            expiresAtEpochMillis = policy.expiresAt?.toEpochMilli(),
        )

        val targets = policy.targets.map { target ->
            target.toEntity(policy.id)
        }

        val conditions = policy.conditions.map { condition ->
            condition.toEntity(policy.id)
        }

        val actions = policy.actions.map { action ->
            ActionEntity(
                policyId = policy.id,
                action = action.name,
            )
        }

        return PersistedPolicy(
            policy = policyEntity,
            targets = targets,
            conditions = conditions,
            actions = actions,
        )
    }

    fun toDomain(
        aggregate: PolicyWithRelations,
    ): BlockadePolicy {
        return BlockadePolicy(
            id = aggregate.policy.id,
            name = aggregate.policy.name,
            source = PolicySource.valueOf(aggregate.policy.source),
            enabled = aggregate.policy.enabled,
            paused = aggregate.policy.paused,
            targets = aggregate.targets.map(TargetEntity::toDomain).toSet(),
            conditions = aggregate.conditions.map(ConditionEntity::toDomain),
            actions = aggregate.actions.map {
                BlockAction.valueOf(it.action)
            }.toSet(),
            conditionMode = ConditionMode.valueOf(
                aggregate.policy.conditionMode,
            ),
            strictness = StrictnessLevel.valueOf(
                aggregate.policy.strictness,
            ),
            expiresAt = aggregate.policy.expiresAtEpochMillis
                ?.let(Instant::ofEpochMilli),
        )
    }

    private fun BlockTarget.toEntity(
        policyId: String,
    ): TargetEntity {
        return when (this) {
            is BlockTarget.Application ->
                TargetEntity(
                    policyId = policyId,
                    type = "APPLICATION",
                    value = packageName,
                    matchingMode = null,
                    contentType = null,
                )

            is BlockTarget.WebDomain ->
                TargetEntity(
                    policyId = policyId,
                    type = "WEB_DOMAIN",
                    value = domain,
                    matchingMode = null,
                    contentType = null,
                )

            is BlockTarget.Keyword ->
                TargetEntity(
                    policyId = policyId,
                    type = "KEYWORD",
                    value = value,
                    matchingMode = matchingMode.name,
                    contentType = null,
                )

            is BlockTarget.AppContent ->
                TargetEntity(
                    policyId = policyId,
                    type = "APP_CONTENT",
                    value = packageName,
                    matchingMode = null,
                    contentType = contentType.name,
                )
        }
    }

    private fun TargetEntity.toDomain(): BlockTarget {
        return when (type) {
            "APPLICATION" ->
                BlockTarget.Application(value)

            "WEB_DOMAIN" ->
                BlockTarget.WebDomain(value)

            "KEYWORD" ->
                BlockTarget.Keyword(
                    value = value,
                    matchingMode = KeywordMatchingMode.valueOf(
                        requireNotNull(matchingMode),
                    ),
                )

            "APP_CONTENT" ->
                BlockTarget.AppContent(
                    packageName = value,
                    contentType = AppContentType.valueOf(
                        requireNotNull(contentType),
                    ),
                )

            else -> error("Unknown target type: $type")
        }
    }

    private fun BlockCondition.toEntity(
        policyId: String,
    ): ConditionEntity {
        return when (this) {
            is BlockCondition.TimeWindow ->
                ConditionEntity(
                    policyId = policyId,
                    type = "TIME_WINDOW",
                    startTime = startTime.toString(),
                    endTime = endTime.toString(),
                    daysOfWeek = daysOfWeek
                        .sortedBy(DayOfWeek::getValue)
                        .joinToString(",") { it.name },
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.UsageLimit ->
                ConditionEntity(
                    policyId = policyId,
                    type = "USAGE_LIMIT",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = limitMinutes,
                    usageScope = scope.name,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.LaunchCount ->
                ConditionEntity(
                    policyId = policyId,
                    type = "LAUNCH_COUNT",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = scope.name,
                    maximumLaunches = maximumLaunches,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.Location ->
                ConditionEntity(
                    policyId = policyId,
                    type = "LOCATION",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = latitude,
                    longitude = longitude,
                    radiusMeters = radiusMeters,
                    locationMode = mode.name,
                    ssid = null,
                )

            is BlockCondition.Wifi ->
                ConditionEntity(
                    policyId = policyId,
                    type = "WIFI",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = ssid,
                )
        }
    }

    private fun ConditionEntity.toDomain(): BlockCondition {
        return when (type) {
            "TIME_WINDOW" ->
                BlockCondition.TimeWindow(
                    startTime = LocalTime.parse(
                        requireNotNull(startTime),
                    ),
                    endTime = LocalTime.parse(
                        requireNotNull(endTime),
                    ),
                    daysOfWeek = requireNotNull(daysOfWeek)
                        .split(',')
                        .filter(String::isNotBlank)
                        .map(DayOfWeek::valueOf)
                        .toSet(),
                )

            "USAGE_LIMIT" ->
                BlockCondition.UsageLimit(
                    limitMinutes = requireNotNull(limitMinutes),
                    scope = UsageScope.valueOf(
                        requireNotNull(usageScope),
                    ),
                )

            "LAUNCH_COUNT" ->
                BlockCondition.LaunchCount(
                    maximumLaunches = requireNotNull(maximumLaunches),
                    scope = UsageScope.valueOf(
                        requireNotNull(usageScope),
                    ),
                )

            "LOCATION" ->
                BlockCondition.Location(
                    latitude = requireNotNull(latitude),
                    longitude = requireNotNull(longitude),
                    radiusMeters = requireNotNull(radiusMeters),
                    mode = LocationMode.valueOf(
                        requireNotNull(locationMode),
                    ),
                )

            "WIFI" ->
                BlockCondition.Wifi(
                    ssid = requireNotNull(ssid),
                )

            else -> error("Unknown condition type: $type")
        }
    }
}

data class PersistedPolicy(
    val policy: PolicyEntity,
    val targets: List<TargetEntity>,
    val conditions: List<ConditionEntity>,
    val actions: List<ActionEntity>,
)
KOTLIN_EOF

echo "== Escribiendo RoomPolicyRepository.kt (sin updatedAt: no existe en el dominio) =="
cat > blockade/src/main/java/com/irrovicas/blockade/data/repository/RoomPolicyRepository.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.repository

import com.irrovicas.blockade.data.local.dao.PolicyDao
import com.irrovicas.blockade.data.local.mapper.PolicyEntityMapper
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.repository.PolicyRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class RoomPolicyRepository(
    private val dao: PolicyDao,
) : PolicyRepository {

    override fun observePolicies(): Flow<List<BlockadePolicy>> {
        return dao.observePolicies()
            .map { policies ->
                policies.map(PolicyEntityMapper::toDomain)
            }
    }

    override suspend fun getPolicy(
        id: String,
    ): BlockadePolicy? {
        return dao.getPolicy(id)
            ?.let(PolicyEntityMapper::toDomain)
    }

    override suspend fun savePolicy(
        policy: BlockadePolicy,
    ) {
        val persisted = PolicyEntityMapper.toEntities(policy)

        dao.replacePolicy(
            policy = persisted.policy,
            targets = persisted.targets,
            conditions = persisted.conditions,
            actions = persisted.actions,
        )
    }

    override suspend fun deletePolicy(
        id: String,
    ) {
        dao.deletePolicyAndChildren(id)
    }

    override suspend fun setEnabled(
        id: String,
        enabled: Boolean,
    ) {
        dao.setEnabled(
            id = id,
            enabled = enabled,
        )
    }

    override suspend fun setPaused(
        id: String,
        paused: Boolean,
    ) {
        dao.setPaused(
            id = id,
            paused = paused,
        )
    }
}
KOTLIN_EOF

echo "== Escribiendo PolicyEntityMapperTest.kt (test JVM, corre con :blockade:test) =="
cat > blockade/src/test/java/com/irrovicas/blockade/data/local/PolicyEntityMapperTest.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.local

import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.mapper.PolicyEntityMapper
import com.irrovicas.blockade.domain.model.AppContentType
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockCondition
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import com.irrovicas.blockade.domain.model.KeywordMatchingMode
import com.irrovicas.blockade.domain.model.LocationMode
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import com.irrovicas.blockade.domain.model.UsageScope
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class PolicyEntityMapperTest {

    @Test
    fun `policy survives domain to entity and back`() {
        val original = BlockadePolicy(
            id = "policy-1",
            name = "Test policy",
            source = PolicySource.SCHEDULE,
            enabled = true,
            paused = false,
            targets = setOf(
                BlockTarget.Application(
                    "com.instagram.android",
                ),
                BlockTarget.WebDomain(
                    "example.com",
                ),
                BlockTarget.Keyword(
                    value = "reels",
                    matchingMode = KeywordMatchingMode.URL_ANYWHERE,
                ),
                BlockTarget.AppContent(
                    packageName = "com.instagram.android",
                    contentType = AppContentType.INSTAGRAM_REELS,
                ),
            ),
            conditions = listOf(
                BlockCondition.TimeWindow(
                    startTime = LocalTime.of(22, 0),
                    endTime = LocalTime.of(2, 0),
                    daysOfWeek = setOf(
                        DayOfWeek.SUNDAY,
                    ),
                ),
                BlockCondition.UsageLimit(
                    limitMinutes = 30,
                    scope = UsageScope.DAILY,
                ),
                BlockCondition.LaunchCount(
                    maximumLaunches = 5,
                    scope = UsageScope.SCHEDULE_WINDOW,
                ),
                BlockCondition.Location(
                    latitude = -12.0464,
                    longitude = -77.0428,
                    radiusMeters = 100f,
                    mode = LocationMode.INSIDE,
                ),
                BlockCondition.Wifi(
                    ssid = "IRROVICAS-HOME",
                ),
            ),
            actions = setOf(
                BlockAction.LAUNCH,
                BlockAction.NOTIFICATION,
            ),
            conditionMode = ConditionMode.ALL,
            strictness = StrictnessLevel.STRICT,
            expiresAt = Instant.parse(
                "2026-08-24T00:00:00Z",
            ),
        )

        val persisted = PolicyEntityMapper.toEntities(original)

        val restored = PolicyEntityMapper.toDomain(
            PolicyWithRelations(
                policy = persisted.policy,
                targets = persisted.targets,
                conditions = persisted.conditions,
                actions = persisted.actions,
            ),
        )

        assertEquals(original.id, restored.id)
        assertEquals(original.name, restored.name)
        assertEquals(original.source, restored.source)
        assertEquals(original.enabled, restored.enabled)
        assertEquals(original.paused, restored.paused)
        assertEquals(original.targets, restored.targets)
        assertEquals(original.conditions, restored.conditions)
        assertEquals(original.actions, restored.actions)
        assertEquals(original.conditionMode, restored.conditionMode)
        assertEquals(original.strictness, restored.strictness)
        assertEquals(original.expiresAt, restored.expiresAt)

        assertNotNull(restored)
    }
}
KOTLIN_EOF

echo "== Escribiendo RoomPolicyRepositoryTest.kt (androidTest, requiere emulador/dispositivo -- no se corre en este script) =="
cat > blockade/src/androidTest/java/com/irrovicas/blockade/data/repository/RoomPolicyRepositoryTest.kt << 'KOTLIN_EOF'
package com.irrovicas.blockade.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.irrovicas.blockade.data.local.db.BlockadeDatabase
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomPolicyRepositoryTest {

    private lateinit var database: BlockadeDatabase
    private lateinit var repository: RoomPolicyRepository

    @Before
    fun setup() {
        val context = ApplicationProvider
            .getApplicationContext<Context>()

        database = Room.inMemoryDatabaseBuilder(
            context,
            BlockadeDatabase::class.java,
        ).build()

        repository = RoomPolicyRepository(
            database.policyDao(),
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun saveAndRetrievePolicy() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-1",
                name = "Instagram focus",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.instagram.android",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
                strictness = StrictnessLevel.NORMAL,
                expiresAt = Instant.parse(
                    "2026-08-23T22:30:00Z",
                ),
            )

            repository.savePolicy(policy)

            val stored = repository.getPolicy("quick-1")

            assertEquals(policy.id, stored?.id)
            assertEquals(policy.name, stored?.name)
            assertEquals(policy.targets, stored?.targets)
            assertEquals(policy.actions, stored?.actions)
            assertEquals(policy.expiresAt, stored?.expiresAt)
        }
    }

    @Test
    fun observePoliciesReturnsSavedPolicy() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-2",
                name = "Focus",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.youtube.android",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)

            val policies = repository
                .observePolicies()
                .first()

            assertEquals(1, policies.size)
            assertEquals("quick-2", policies.single().id)
        }
    }

    @Test
    fun disablingPolicyIsPersisted() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-3",
                name = "Disable test",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.example.app",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)
            repository.setEnabled("quick-3", false)

            val stored = repository.getPolicy("quick-3")

            assertEquals(false, stored?.enabled)
        }
    }

    @Test
    fun deletingPolicyRemovesIt() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-4",
                name = "Delete test",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.example.app",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)
            repository.deletePolicy("quick-4")

            val stored = repository.getPolicy("quick-4")

            assertEquals(null, stored)
        }
    }
}
KOTLIN_EOF

echo "OK: 9 archivos Kotlin nuevos escritos + 2 build.gradle.kts reescritos."

echo "== Corriendo ./gradlew :blockade:test =="
./gradlew :blockade:test

echo "== Corriendo ./gradlew :blockade:assembleDebug =="
./gradlew :blockade:assembleDebug

echo "== Estado en git =="
git add -A
git status --short

echo "============================================================"
echo "Fase 2.6 (Room persistence) escrita y compilada en JVM."
echo ""
echo "Qué cambié respecto al plan de ChatGPT (y por qué):"
echo "  1. PolicyEntity / mapper / RoomPolicyRepository ya NO tienen"
echo "     createdAt/updatedAt. BlockadePolicy (dominio real) no tiene"
echo "     esos campos -- el plan original asumía que sí, y con eso"
echo "     tal cual no compilaba (policy.createdAt, policy.copy(updatedAt=...)"
echo "     no existen). No se los agregué al dominio: no era lo que pediste."
echo "  2. PolicyDao.observePolicies() ordena por 'id ASC' en vez de"
echo "     'updatedAtEpochMillis DESC', porque esa columna ya no existe."
echo "  3. setEnabled/setPaused (DAO y RoomPolicyRepository) ya no reciben"
echo "     ni escriben updatedAtEpochMillis, por la misma razón."
echo "  4. Agregué 'testInstrumentationRunner = \"androidx.test.runner.AndroidJUnitRunner\"'"
echo "     en blockade/build.gradle.kts -- sin eso, connectedDebugAndroidTest"
echo "     no encuentra el runner. ChatGPT no lo incluyó."
echo ""
echo "Lo demás (entities de targets/conditions/actions, DAO, Room database,"
echo "el mapper de targets/conditions, KSP 2.3.9 + Room 2.8.4) va tal cual"
echo "lo propuso ChatGPT -- lo verifiqué campo por campo contra el dominio"
echo "real del repo y matchea."
echo ""
echo "Para commitear y subir:"
echo "  git commit -m \"feat(blockade): Room persistence (Fase 2.6) - RoomPolicyRepository, entities, DAO, mapper\""
echo "  git push origin <tu-rama>"
echo ""
echo "Pendiente, fuera de este script (necesita emulador/dispositivo):"
echo "  ./gradlew :blockade:connectedDebugAndroidTest"
echo "Ese comando corre RoomPolicyRepositoryTest.kt (4 tests) contra SQLite"
echo "real. Codespaces normalmente no trae un emulador levantado, así que"
echo "no lo metí en el script automático -- corre eso aparte si tienes"
echo "cómo, y mándame la salida."
echo ""
echo "Próximo paso (Fase 3, según lo que ya viste del repo real):"
echo "  Room ya reemplaza a InMemoryPolicyRepository como implementación"
echo "  de PolicyRepository. Falta decidir dónde se inyecta RoomPolicyRepository"
echo "  vs InMemoryPolicyRepository (MainActivity, o un punto de composición"
echo "  de dependencias aparte) -- eso no lo tocó este script a propósito."
echo "============================================================"
