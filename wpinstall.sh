# Wordpress installation setup

#!/bin/bash -e

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
NC='\033[0m' # No Color

clear

echo -e "${BLU}================================================================="
echo -e "Awesome WordPress Installer!!"
echo -e "=================================================================${NC}"

echo

echo -e "${GRN}Enter path to create new directory for installation, or just enter to install at current location:${NC}"
read -e directory

# Check if string is empty using -z. For more 'help test'    
if [[ -z "$directory" ]]; then
	echo -e "Installing in: ${PWD}"
else
   # If user input is not empty check directory does not exist then continue
   while [ -d $directory ]
	do
	  echo -e "That directory already exists - try again?"
	  read -e directory
	done
   mkdir $directory
   cd $directory
   echo -e "Installing in: ${PWD}"   
fi

# parse the current directory name
currentdirectory=${PWD##*/}

# database user
echo -e "${GRN}Enter MySQL database username (must already exist):${NC}"
read -e dbuser

unset dbpass
echo -e "${GRN}Enter MySQL database password:${NC}"
prompt=""
while IFS= read -p "$prompt" -r -s -n 1 char
do
    if [[ $char == $'\0' ]]
    then
        break
    fi
    prompt='*'
    dbpass+="$char"
done

echo

# database name
echo -e "${GRN}Enter new MySQL database name (database will be created):${NC}"
read -e dbname

# accept the name of our website
echo -e "${GRN}Enter name for the Wordpress site:${NC}"
read -e sitename

# accept the uadmin username for our website
echo -e "${GRN}Enter username for the main admin user for the Wordpress site:${NC}"
read -e wpuser

# accept a comma separated list of pages
echo -e "${GRN}Add Pages to be created (multiple pages should be separated by a comma, 'home' will be created by default):${NC}"
read -e allpages

# accept a comma separated list of plugins
echo -e "${GRN}To install plugins, list their short names in a comma-separated list (press enter to ignore):${NC}"
read -e plugins

# get theme option to install
echo -e "${GRN}To install a theme, enter the theme short name (press enter to ignore):${NC}"
read -e theme

# add a simple yes/no confirmation before we proceed
echo -e "${GRN}Start installation process? (y/n)${NC}"
read -e run

# if the user didn't say no, then go ahead an install
if [ "$run" == n ] ; then
	exit
else

# download the WordPress core files
wp core download

# create the wp-config file with our standard setup
wp core config --dbhost=127.0.0.1 --dbname=$dbname --dbuser=$dbuser --dbpass=$dbpass --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'DISALLOW_FILE_EDIT', true );
PHP

# generate random 12 character password
password=$(LC_CTYPE=C tr -dc A-Za-z0-9_\!\@\#\$\%\^\&\*\(\)-+= < /dev/urandom | head -c 12)

# copy password to clipboard
echo $password | pbcopy

# create database, and install WordPress
if mysql --user=$dbuser --password=$dbpass -e "use $dbname"; then
	echo -e "${RED}That database already exists - do you want to drop it and continue (y)? Enter 'n' to exit${NC}"
	read -e drop
	if [ "$drop" == y ] ; then
		wp db drop --yes
		wp db create
	elif [ "$drop" == n ] ; then
		echo -e "${RED}Cancelling installation${NC}"
		exit
	fi
else
	wp db create
fi

wp core install --url="http://localhost/$currentdirectory" --title="$sitename" --admin_user="$wpuser" --admin_password="$password" --admin_email="info@pjsweb.uk"

# discourage search engines
wp option update blog_public 0

# show only 6 posts on an archive page
# wp option update posts_per_page 6

# delete sample page, and create homepage
echo -e "Deleting sample page/post"
wp post delete $(wp post list --post_type=page --posts_per_page=1 --post_status=publish --pagename="sample-page" --field=ID --format=ids) --force
wp post delete $(wp post list --post_type=post --posts_per_page=1 --post_status=publish --postname="hello-world" --field=ID --format=ids) --force
echo -e "Creating Home page"
wp post create --post_type=page --post_title=Home --post_status=publish --post_author=$(wp user get $wpuser --field=ID --format=json)

# set homepage as front page
echo -e "Setting Home as front page"
wp option update show_on_front 'page'

# set homepage to be the new page
wp option update page_on_front $(wp post list --post_type=page --post_status=publish --posts_per_page=1 --pagename=home --field=ID --format=ids)

# create all of the pages
export IFS=","
for page in $allpages; do
	echo -e "Creating ${page} page..."
	wp post create --post_type=page --post_status=publish --post_author=$(wp user get $wpuser --field=ID --format=json) --post_title="$(echo $page | sed -e 's/^ *//' -e 's/ *$//')"
done




# set pretty urls
# echo -e "Creating .htaccess file"
wp rewrite structure
wp rewrite flush --hard

# delete akismet and hello dolly
# wp plugin delete akismet
echo -e "Deleting 'hello' plugin..."
wp plugin delete hello

# install and activate any plugins
if [ ! -z "$plugins" ]
then
	export IFS=","
	for plugin in $plugins; do
		echo -e "Installing and activating ${plugin} plugin..."
		wp plugin install $plugin --activate
	done
fi

# Check if theme requested
if [ ! -z "$theme" ]
then
    echo -e "Installing and activating ${theme} theme..."
	wp theme install $theme --activate
fi



# install lt-tables plugin
# wp plugin install https://github.com/ltconsulting/lt-tables/archive/master.zip --activate

# install antispam plugin
# wp plugin install antispam-bee --activate

# install the company starter theme
# wp theme install ~/Documents/lt-theme.zip --activate

#clear

# create a navigation bar
echo -e "Creating Main Navigation menu"
wp menu create "Main Navigation"

# add pages to navigation
echo -e "Adding pages to Main Navigation menu"
export IFS=" "
for pageid in $(wp post list --order="ASC" --orderby="date" --post_type=page --post_status=publish --posts_per_page=-1 --field=ID --format=ids); do
	wp menu item add-post main-navigation $pageid
done

# assign navigaiton to primary location
echo -e "Setting Main Navigation to be primary menu"
wp menu location assign main-navigation menu-1 || wp menu location assign main-navigation primary


echo -e "${BLU}================================================================="
echo -e "Installation is complete. Your username/password is listed below."
echo -e ""
echo -e "Username: $wpuser"
echo -e "Password: $password"
echo -e ""
echo -e "=================================================================${NC}"

ln -s $PWD /Applications/MAMP/htdocs/$currentdirectory

# Open the new website with Google Chrome
/usr/bin/open -a "/Applications/Google Chrome.app" "http://localhost/$currentdirectory/wp-login.php"


fi