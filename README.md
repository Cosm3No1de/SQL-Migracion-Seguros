# Insurance Data Migration Project

Un proyecto end-to-end simulando la migración de datos de un sistema de aseguradora legado (datos "sucios" e inconsistentes) hacia un Modelo de Estrella (Star Schema) optimizado y listo para análisis por parte de los equipos de Business Intelligence y Actuarios.

## 🎯 Problemática
Migración de un sistema legado con datos inconsistentes (formatos de fecha mixtos, strings corruptos, registros duplicados, valores atípicos y campos obligatorios nulos) a un esquema analítico relacional.

## 🛠️ Tecnologías
- **PostgreSQL**
- **SQL Avanzado**: Uso extensivo de uniones (JOINs), type CASTing, funciones sobre Strings, sentencias condicionales (CASE WHEN), e Interval Arithmetic (cálculos de expiración en dimensión temporal).

## ⭐ Highlight Técnico
- **Data Scrubbing & Transformation**: Implementación de lógica de limpieza de datos en tablas "Staging" temporales antes de ser consolidados en el Data Warehouse.
- **Error Handling en Datos**: Diseño de una tabla de auditoría capturando las divergencias o datos corruptos en formato `JSONB` para ser expuestos como alertas a procesos de QA, evitando pérdidas financieras por pérdida silenciosa de registros.
- **Idempotencia**: Funciones estructuradas con `ON CONFLICT DO NOTHING` para habilitar que el pipeline se ejecute múltiples veces de forma segura alimentando Dimensiones maestras.

## ⚡ Performance
- **Query Tuning & Indexing**: Uso de indexación estratégica por llaves foráneas (`ClienteID`) y ventanas de tiempo (fechas de inicio y expiración de formato B-Tree) para eficientar los reportes de vigencia y KPIs de los procesos de BI asegurando latencias mínimas.
