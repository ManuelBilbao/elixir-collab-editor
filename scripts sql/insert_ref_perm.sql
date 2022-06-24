DELETE from permisos_referencia;
insert into permisos_referencia 
values (1, "LECTURA", 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
insert into permisos_referencia 
values (2, "ESCRITURA", 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
insert into permisos_referencia 
values (3, "ADMIN", 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
insert into permisos_referencia 
values (4, "CREADOR", 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
select * from permisos_referencia;