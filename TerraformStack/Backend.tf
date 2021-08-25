terraform {
  backend "consul" {
//    address = "127.0.0.1:8500"
    address = "host.docker.internal:8500"
    scheme = "http"
  }
}