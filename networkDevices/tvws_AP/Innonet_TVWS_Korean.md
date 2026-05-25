Resumen de la configuración de los
equipos Innonet TVWS

Introducción

Este documento es un resumen del proceso de montaje de un sistema, 1:1, MASTER -
SLAVE de TVWS, con algunas anotaciones y recomendaciones generales, es importante
que primero se configure el equipo MASTER y luego el equipo SLAVE, para evitar
problemas de configuración con los equipos, y es más importante, evitar modificaciones de
las direcciones IP de las interfaces de red de los equipos, a lo largo de este documento sé
irá detallando cuáles son las direcciones IP que debe tener en cuenta para acceder a los
equipos y para configurar los mismos.

Configuración del Nodo Master

Para la configuración del nodo MASTER es necesario conectarse a la interfaz LAN del
equipo y poner una dirección IP estática al mismo, la dirección IP del equipo es la
192.168.100.1

Interfaz web:

Debemos entrar a la configuración Network y de ahí a Wirless/DB:

Para pruebas de laboratorio donde la distancia puede ser muy pequeña, hay que bajar la
potencia de transmisión del equipo, en este caso la potencia mínima son 14dBm, hay que
asegurarse de que el modo de operación del equipo este en MASTER, en este caso el
ancho de banda del equipo se ha dejado en 6MHz, y la frecuencia central en 575MHz, como
recomendación general es mejor verificar ocupación del canal o canales que se deseen
utilizar para evitar interferencia.

Luego de realizar los cambios es necesario guardarlos al final de la página encontrará las
opciones, como recomendación, es necesario darle save, que hace un guardado rápido de
las configuraciones; y luego save and apply, que hace un guardado y un restart de las
configuraciones del equipo.

Configuración del equipo Worker/Slave

Por defecto, todos los equipos de TVWS estan configurados como MASTER, es decir que al
empezar la configuración del segundo equipo el acceso a la interfaz de administración será
igual que las del paso anterior, pero, en la seción de Network -> Wirless/DB se deberá
cambiar la configuración a SLAVE, las demas configuraciones deben ser iguales a las del
nodo MASTER, y es importante que el SSID de ambos equipos sea el mismo.

De igual forma es necesario guardar los cambios como se hizo con el equipo anterior, en
este caso, luego de darle save and apply, será necesario que hagamos un reboot del
equipo

Es probable que al llegar a este punto haya algún warning diciendo que hay configuraciones
no guardadas; en la esquina superior derecha podrá ver una opción de unsave changes,
para verificar dichos cambios, por lo general es un cambio de la temperatura de operación
del equipo, que se cambia de forma automatica, basta con darle save y continuar con el
proceso.

Después de un tipo, unos 2 minutos, perdera la conección con el dispositivo porque la IP del
mismo ha cambiado a la 192.168.1.1, basta con cambiar la IP del equipo usado para la
configuración para poder volver a acceder nuevamente a la interfaz web, las credenciales
de acceso son las mismas.

Una vez haya reiniciado se puede verificar conexión entre los dispositivos,por medio del
enlace radio:

Ambos dispositivos debería tener los indicadores led de link en verde:

Del lado del SLAVE, y el MASTER podra ver en Network -> Status/settings el estado actual
del link, en caso de no haber link debería verificar la línea de vista

Como anotación, esta es la distancia que hay en laboratorio del equipo SLAVE y el
MASTER, sería recomendable empezar a una distancia de 2 metros e ir verificando enlace,
para este caso particular.

Configuración de la salida a internet

La salida a internet en este sistema se realiza por medio del equipo MASTER, para ello hay
que conectar y configurar la interfaz WAN del dispositivo

Como recomendación, y para simplicidad del montaje, es altamente recomendable
conectar esta interfaz a un servidor DHCP, en el apartado de Network -> interface, podrá
encontrar las dos interfaces del dispositivo (tenga en cuenta que estamos conectados al
MASTER), por defecto la interfaz WAN esta configurada como DHCP Client, por lo cual
debería conectarse de forma automática pasado un tiempo (puede tardarse un poco)

Podemos verificar la configuración de la interfaz y en caso de quererlo, configurar una IP
estatica, en caso de hacerlo, se le recomienda que haga un reboot del dispositivo para que
el cambio sea efectivo.

Configuración y conexión de los clientes:

Desde un equipo cliente puede intentar conectarse a la red wifi del equipo SLAVE

Esta red le dará una dirección IP en la red: 192.168.25.0/24, como anotación importante,
tenga en cuenta que la velocidad de navegación de los clientes dependerá de la calidad del
enlace radio entre el MASTER y el SLAVE

Desde un equipo cliente podrá entrar a la configuración WiFi por medio de la interfaz web
en la dirección http://192.168.25.1 el usuario es root y la contraseña es fts

Desde el apartado de Networ> WiFi, podrá ver la lista de clientes actuales de la red y
también entrar al apartado de configuración de la misma

Desde la opción de editar de la red podrá modificar cosas como: el SSID de la red, es
recomendable que el nombre de este parámetro no sea muy largo, puede causar problemas
al momento de actualizarse, y la potencia de transmisión del equipo (para la red WiFi, esta
es una potencia distinta a la que hemos tratado anteriormente)

Para cambiar cualquiera de estos parámetros es necesario, hacer el proceso de guardado
ya mencionado con anterioridad, save, save and apply, y adicionalmente hacer un reboot,
del equipo para que los cambios sean efectivos