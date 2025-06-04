CREATE SCHEMA stage;
CREATE SCHEMA core;
CREATE SCHEMA mart;

CALL load_from_stage();

