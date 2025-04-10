output "vpc_id" {
  value = aws_vpc.task16_vpc.id
}

output "wordpress_db_endpoint" {
  value = aws_db_instance.task16_wordpress_db.address
}

output "alb_dns_name" {
  value = aws_lb.task16_alb.dns_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.task16_wordpress_sns.arn
}

