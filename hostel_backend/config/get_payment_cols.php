<?php
$c = new mysqli('localhost', 'root', 'vstay2026', 'stay_simats');
if ($c->connect_error) die("Connection failed: " . $c->connect_error);
$r = $c->query('DESCRIBE payment');
while($f = $r->fetch_assoc()) echo $f['Field'] . "\n";
?>
