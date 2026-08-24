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
