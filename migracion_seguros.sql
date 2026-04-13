-- 1. Tabla de Clientes (Dimension)
CREATE TABLE Dim_Clientes (
    ClienteID SERIAL PRIMARY KEY,
    CodigoExterno VARCHAR(50) UNIQUE, -- El ID que venía del sistema viejo
    NombreCompleto VARCHAR(255),
    Email VARCHAR(100),
    FechaRegistro DATE DEFAULT CURRENT_DATE
);

-- 2. Tabla de Coberturas
CREATE TABLE Dim_Coberturas (
    CoberturaID SERIAL PRIMARY KEY,
    TipoCobertura VARCHAR(100), -- Ej: 'P&C - Auto', 'P&C - Home'
    Descripcion TEXT
);

-- 3. Tabla de Pólizas (Fact Table)
CREATE TABLE Fact_Polizas (
    PolizaID SERIAL PRIMARY KEY,
    ClienteID INT REFERENCES Dim_Clientes(ClienteID),
    CoberturaID INT REFERENCES Dim_Coberturas(CoberturaID),
    FechaInicio DATE,
    FechaFin DATE,
    PrimaMonto DECIMAL(15, 2), -- El costo del seguro
    Estado VARCHAR(20), -- 'Activa', 'Vencida', 'Cancelada'
    CONSTRAINT fk_cliente FOREIGN KEY (ClienteID) REFERENCES Dim_Clientes(ClienteID)
);

-- Staging
CREATE TABLE STG_Migracion_Seguros (
    Raw_Nombre VARCHAR(255),
    Raw_Email VARCHAR(255),
    Raw_Tipo_Seguro VARCHAR(100),
    Raw_Monto VARCHAR(100),    -- Viene como texto, a veces con símbolos de $
    Raw_Fecha_Inicio VARCHAR(100), -- Viene en formato DD/MM/YYYY o YYYY-MM-DD
    Raw_Duracion_Meses INT
);

-- Inserción de Datos Sucios
INSERT INTO STG_Migracion_Seguros VALUES 
('ALEXIS SUCH', 'alexis@mail.com', 'AUTO', '$1200.50', '2026-01-01', 12),
('mariel giudice', 'MARIEL@MAIL.COM', 'home', '850.00', '05/03/2026', 6),
('ALEXIS SUCH', 'alexis@mail.com', 'AUTO', '$1200.50', '2026-01-01', 12), -- DUPLICADO
('Conejita Cat', NULL, 'LIFE', 'invalid_amount', '2026-04-13', 24); -- DATO CORRUPTO

-- ==========================================
-- PASO 4: Limpieza (Data Scrubbing)
-- ==========================================
-- Consultamos la tabla de Staging aplicando transformaciones en tiempo real
SELECT DISTINCT -- Esto elimina las filas exactamente iguales (como el duplicado de Alexis)
    UPPER(TRIM(Raw_Nombre)) AS Nombre_Limpio,
    LOWER(Raw_Email) AS Email_Limpio,
    UPPER(Raw_Tipo_Seguro) AS Tipo_Seguro,
    -- Quitamos el signo $ y convertimos a DECIMAL. Si no es número, ponemos 0.
    CAST(NULLIF(REPLACE(Raw_Monto, '$', ''), 'invalid_amount') AS DECIMAL(15,2)) AS Monto_Limpio,
    -- Intentamos convertir la fecha (PostgreSQL es muy inteligente con TO_DATE)
    CASE 
        WHEN Raw_Fecha_Inicio LIKE '%/%' THEN TO_DATE(Raw_Fecha_Inicio, 'DD/MM/YYYY')
        ELSE CAST(Raw_Fecha_Inicio AS DATE)
    END AS Fecha_Inicio_Limpia
FROM STG_Migracion_Seguros
WHERE Raw_Email IS NOT NULL; -- Filtramos datos corruptos sin email (como el de Conejita)

-- ==========================================
-- PASO 5: Carga a Dimensiones (Loading)
-- ==========================================

-- 1. Cargar Clientes
INSERT INTO Dim_Clientes (CodigoExterno, NombreCompleto, Email)
SELECT DISTINCT 
    Raw_Email, -- Usamos el email como código externo temporal
    UPPER(TRIM(Raw_Nombre)), 
    LOWER(Raw_Email)
FROM STG_Migracion_Seguros
WHERE Raw_Email IS NOT NULL
ON CONFLICT (CodigoExterno) DO NOTHING; -- Evita errores si el cliente ya existe

-- 2. Cargar Coberturas
INSERT INTO Dim_Coberturas (TipoCobertura)
SELECT DISTINCT UPPER(Raw_Tipo_Seguro)
FROM STG_Migracion_Seguros
ON CONFLICT DO NOTHING;

-- ==========================================
-- PASO 6: Carga de la Fact Table (The Big Join)
-- ==========================================
INSERT INTO Fact_Polizas (ClienteID, CoberturaID, FechaInicio, FechaFin, PrimaMonto, Estado)
SELECT 
    c.ClienteID, 
    cob.CoberturaID,
    -- Aplicamos la misma lógica de limpieza de fechas que probamos antes
    CASE 
        WHEN stg.Raw_Fecha_Inicio LIKE '%/%' THEN TO_DATE(stg.Raw_Fecha_Inicio, 'DD/MM/YYYY')
        ELSE CAST(stg.Raw_Fecha_Inicio AS DATE)
    END AS FechaInicio,
    -- Calculamos la Fecha de Fin sumando la duración en meses a la fecha de inicio
    (CASE 
        WHEN stg.Raw_Fecha_Inicio LIKE '%/%' THEN TO_DATE(stg.Raw_Fecha_Inicio, 'DD/MM/YYYY')
        ELSE CAST(stg.Raw_Fecha_Inicio AS DATE)
    END + (stg.Raw_Duracion_Meses || ' months')::INTERVAL)::DATE AS FechaFin,
    -- Limpieza de montos
    CAST(NULLIF(REPLACE(stg.Raw_Monto, '$', ''), 'invalid_amount') AS DECIMAL(15,2)),
    'Activa' -- Seteamos un estado por defecto para la migración
FROM STG_Migracion_Seguros stg
-- Cruzamos con Clientes usando el Email como llave de negocio
JOIN Dim_Clientes c ON LOWER(stg.Raw_Email) = c.Email
-- Cruzamos con Coberturas usando el tipo de seguro
JOIN Dim_Coberturas cob ON UPPER(stg.Raw_Tipo_Seguro) = cob.TipoCobertura
-- Evitamos cargar datos que sabemos que están corruptos (como el de Conejita que no tiene email)
WHERE stg.Raw_Email IS NOT NULL 
  AND stg.Raw_Monto <> 'invalid_amount';

-- ==========================================
-- PASO FINAL: Verificación Profesional
-- ==========================================
SELECT 
    p.PolizaID,
    c.NombreCompleto AS Cliente,
    cob.TipoCobertura AS Seguro,
    p.FechaInicio,
    p.FechaFin,
    p.PrimaMonto AS Costo
FROM Fact_Polizas p
JOIN Dim_Clientes c ON p.ClienteID = c.ClienteID
JOIN Dim_Coberturas cob ON p.CoberturaID = cob.CoberturaID;

-- ==========================================
-- PASO 7: Índices para el Rendimiento (Query Tuning)
-- ==========================================
-- Creamos índices para optimizar las consultas de negocio más frecuentes
CREATE INDEX idx_fact_polizas_cliente ON Fact_Polizas(ClienteID);
CREATE INDEX idx_fact_polizas_fechas ON Fact_Polizas(FechaInicio, FechaFin);

-- ==========================================
-- PASO 8: Tabla de Auditoría (Error Handling)
-- ==========================================
-- Creamos una tabla para los registros que no pasaron el control de calidad
CREATE TABLE Log_Errores_Migracion (
    ErrorID SERIAL PRIMARY KEY,
    Raw_Data JSONB, -- Guardamos toda la fila original como JSON
    Motivo_Error TEXT,
    Fecha_Error TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insertamos en la tabla de errores lo que filtramos antes
INSERT INTO Log_Errores_Migracion (Raw_Data, Motivo_Error)
SELECT 
    to_jsonb(stg.*), 
    'Email nulo o Monto inválido'
FROM STG_Migracion_Seguros stg
WHERE Raw_Email IS NULL OR Raw_Monto = 'invalid_amount';
