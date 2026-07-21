output "instance_id" {
  value = aws_instance.mongo_vm.id
}

output "public_ip" {
  value = aws_instance.mongo_vm.public_ip
}

output "private_ip" {
  value = aws_instance.mongo_vm.private_ip
}

output "security_group_id" {
  value = aws_security_group.mongo_vm.id
}