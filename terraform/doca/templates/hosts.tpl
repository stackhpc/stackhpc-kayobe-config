[compute]
%{ for element in compute_hostname ~}
${ element }
%{ endfor ~}
