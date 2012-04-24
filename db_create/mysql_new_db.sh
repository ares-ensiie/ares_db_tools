#!/bin/bash

MYSQL_SERVER=bertha.ares
LDAP_SERVER_URL=ldap://faxe.ares
MYSQL_PASSFILE=/etc/.mysql.secret
LDAP_PASSFILE=/etc/pam_ldap.secret
LDAP_EMAIL_ATTR=aresEmail

send_email()
{
  cat > mail.tmp <<EOF
Subject: Création de base de données MySQL

Salut !

Une base de donnée a été ouvert pour ton utilisation.

Serveur : $MYSQL_SERVER
Base de donnée : $1
Utilisateur : $1
Mot de passe : $3

Tu pourras trouver des informations sur notre wiki : http://wiki.ares-ensiie.eu

Profites-en bien. Pour tout question ou problème, rendez vous sur http://bug.ares-ensiie.eu

--
L'équipe ARES
EOF

  cat mail.tmp | iconv -f utf-8 -t ISO8859-1 | /usr/sbin/sendmail -F "Contact ARES" -f "contact@ares-ensiie.eu" $2
  rm mail.tmp
}



if [ $# -ne 1 ]
then
  echo "$0 <username>"
  exit -1
fi

if [ -f "$MYSQL_PASSFILE" ]
then
  mysql_password=`cat "$MYSQL_PASSFILE"`
else
  echo "Unable to find $MYSQL_PASSFILE"
  exit 1
fi

db_list=`mysql --user=root --password="$mysql_password" <<EOF
SHOW DATABASES;
EOF`

if [ `echo "$db_list" | grep -c $1` -eq 1 ]
then
  echo "Database for user $1 already exists"
  exit 1
fi

user_password=`apg -n1 -m16 -a0`

mysql --user=root --password="$mysql_password" <<EOF
CREATE DATABASE $1;
GRANT ALL PRIVILEGES ON $1.* TO '$1'@'%' IDENTIFIED BY '$user_password';
EOF

echo "Database created for user $1 with password $user_password"


if [ `getent passwd | grep -c $1` -ne 1 ]
then
  echo "The user doesn't seem to be a regular user, nothing has been done"
  exit 0
else
  if [ -f "$LDAP_PASSFILE" ]
  then
    ldap_password=`cat "$LDAP_PASSFILE"`
  else
    echo "Unable to find $LDAP_PASSFILE"
    echo "$0 email can't be retrieved,"
    echo "The user $0 has NOT been notified !"
    exit 1
  fi

  res=`ldapsearch -H $LDAP_SERVER_URL -LLL -w "$ldap_password" -D 'cn=admin,dc=ares' -b 'ou=users,dc=ares' "(&(objectClass=aresAccount)(cn=$1))" $LDAP_EMAIL_ATTR`
  user_email=`echo $res | grep $LDAP_EMAIL_ATTR | cut -d' ' -f 4`
  send_email $1 $user_email $user_password

  echo "The user $1 has been notified by email ($user_email)"
fi
