# Relais SSH minimal : n'accepte qu'un tunnel inverse (aucun shell, aucune commande)
FROM alpine:3.20
RUN apk add --no-cache openssh-server \
 && adduser -D -s /sbin/nologin tunnel \
 && sed -i 's/^tunnel:!/tunnel:*/' /etc/shadow \
 && ssh-keygen -A
COPY sshd_config /etc/ssh/sshd_config
COPY authorized_keys /home/tunnel/.ssh/authorized_keys
RUN chown -R tunnel:tunnel /home/tunnel/.ssh && chmod 700 /home/tunnel/.ssh && chmod 600 /home/tunnel/.ssh/authorized_keys
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
