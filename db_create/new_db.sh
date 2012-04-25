#!/bin/bash

if [ $UID -ne 0 ]
then
  echo "Please, run as root."
  exit -1
fi

LDAP_SERVER_URL=ldap://faxe.ares
LDAP_PASSFILE=/etc/pam_ldap.secret
LDAP_EMAIL_ATTR=aresEmail
source email_notification

usage()
{
  echo "$0 -t <MySQL|PgSQL> -u <User>"
  exit 0
}

while getopts "t:u:" opt
do
  case "$opt" in
    t)
      if [ `echo $OPTARG | grep -Eic "mysql|pgsql"` -ne 1 ]
      then
        usage $0
      else
        sgdb=$OPTARG
      fi
      ;;
    u)
      username=$OPTARG
      ;;
    *)
      usage $0 
      ;;
  esac
done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              

[ -z $username -o -z $sgdb ] && usage $0

if [ `echo "$sgdb" | grep -ic "mysql"` -eq 1 ]
then
  sgdb="MySQL"
  source mysql_functions
elif [ `echo "$sgdb" | grep -ic "pgsql"` -eq 1 ]
then
  sgdb="PostgreSQL"
  source pgsql_functions
else
  usage $0
fi

list_db=$(list_db)

if [ `echo "$list_db" | grep -c $username` -eq 1 ]
then
  echo "Database for user $username already exists"
  exit 1
fi

user_password=`apg -n1 -m16 -a0`

create_db $username $user_password

echo "Database created for user $username with password $user_password"

if [ `getent passwd | grep -c $username` -ne 1 ]
then
  echo "The user doesn't seem to be a regular user."
  echo -n "Do you want to send a notification by email ? [Yn] "
  read res
  if [ "$res" = "y" -o "$res" = "Y" -o -z "$res" ]
  then
    echo -n "Email address : "
    read user_email
    send_email $username $user_email $user_password $sgdb $HOST_DB
    echo "An email has been sent to $user_email, bye bye."
  else
    echo "Ok, keep the password, bye bye."
  fi
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

  res=`ldapsearch -H $LDAP_SERVER_URL -LLL -w "$ldap_password" -D 'cn=admin,dc=ares' -b 'ou=users,dc=ares' "(&(objectClass=aresAccount)(uid=$username))" $LDAP_EMAIL_ATTR`
  user_email=`echo $res | grep $LDAP_EMAIL_ATTR | cut -d' ' -f 4`
  send_email $username $user_email $user_password $sgdb $HOST_DB

  echo "The user $username has been notified by email ($user_email)"
fi
