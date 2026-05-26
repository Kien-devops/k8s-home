consul {
  address = "consul:8500"
}

template {
  source      = "/consul-template/templates/haproxy.cfg.ctmpl"
  destination = "/generated/haproxy.cfg"
  perms       = 0644
  command     = "sh -c '[ \"$(cat /proc/1/comm 2>/dev/null)\" = \"haproxy\" ] && kill -USR2 1 || true'"
  wait {
    min = "2s"
    max = "10s"
  }
}
