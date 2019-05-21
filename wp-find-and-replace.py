#!/usr/bin/python
#Written by Dominic Hiles, May 2008 - http://www.ilrt.bris.ac.uk/aboutus/staff/staffprofile/?search=bzdnh
#Copyright and intellectual property rests with the University of Bristol
#Argument parsing based on repozo.py (Zope) - FIXME: Copyright?
"""
wp-find-and-replace.py -- performs a find & replace in a Wordpress MySQL database dump, fixing up the length of serialzed arrays as required.

USAGE: %(program)s -f "string-to-find" -r "string-to-replace" -i /path/to/database dump [-o /path/to/ouput] [-c character-set][-s]

WHERE:

-f The search string to find
-r The string to replace it with
-i The path to the database dump
-o The path to the ouput file, optional but recommended, overwrites existing file if not provided
-c The character set of the dump file, optional, defaults to utf8
-s Using this flag will cause only the "siturl" and "home" values in the dump to be replaced - these are the two URLs presented in the Wordpress admin screen (in 2.3.3 at least)
"""
import os, os.path
import sys
import getopt
import re

program = sys.argv[0]
VERBOSE = 1

def log(msg, code=1, *args):
    outfp = sys.stderr
    if code == 0:
        outfp = sys.stdout
    
    if code == 1 or VERBOSE:
        print >> outfp, msg % args

def usage(code, msg=''):
    outfp = sys.stderr
    if code == 0:
        outfp = sys.stdout

    print >> outfp, __doc__ % globals()
    if msg:
        print >> outfp, msg

    sys.exit(code)

class Options:
    site_only = False
    character_set = 'utf8'
    find_string = ""
    replace_with_string = ""
    source_file = None
    out_file = None

def parseargs():
    try:
        opts, args = getopt.getopt(sys.argv[1:], 'sf:r:i:o:c:')
    except getopt.error, msg:
        usage(1, msg)

    options = Options()

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage(1)
        elif opt in ('-f'):
            options.find_string = arg
        elif opt in ('-r'):
            options.replace_with_string = arg
        elif opt in ('-i'):
            options.source_file = arg
        elif opt in ('-o'):
            options.out_file = arg
        elif opt in ('-s'):
            options.site_only = True         
        elif opt in ('-c'):
            options.character_set = arg         
        else:
            assert False, (opt, arg)

    # Any other arguments are invalid
    if args:
        usage(1, 'Invalid arguments: ' + ', '.join(args))

    if options.source_file is None:
        usage(1, 'You must specify a file to check.')

    if not options.find_string:
        usage(1, 'You must specify a string to search for.')        
     
    if options.out_file is None:
        options.out_file = options.source_file[:]
    
    options.find_string = unicode(options.find_string, options.character_set)
    options.replace_with_string = unicode(options.replace_with_string, options.character_set)
        
    return options

def readFile(path, readmode='r'):
    """Open file and return contents as string"""
    f = None
    contents = ''

    if os.path.exists(path):
        try:
            try:
                f = open(path, readmode)
            except:
                raise ValueError, "Unable to open %s" % path

            contents = f.read()
            f.close()
        finally:
            if f is not None:
                f.close()
    else:
        log ("%s does not exist" % path)

    return contents

def writeFile(path, text):
    """Writes a string to a file"""
    f = None
    contents = ''

    try:
        try:
            f = open(path, 'w')
        except:
            raise ValueError, "Unable to open %s" % path
        
        f.write(text)
        f.close()
    finally:
        if f is not None:
            f.close()

    return


def doReplace(options):
    """Do the actualy find and replace"""
    assert isinstance(options, Options)

    source_text = unicode(readFile(options.source_file),options.character_set)
    return_text = source_text[:]
    changes = 0
    
    if options.site_only:
        #This is easy - we search for the two urls:
        #e.g. 'siteurl','http://www.mydomain.com/blog'
        #and then replace only in those locations
        home_regexes = re.compile("'(?:siteurl|home)','[^']*'", re.DOTALL | re.UNICODE)
        search_locns = home_regexes.finditer(source_text)
        for location in search_locns:
            match = location.group()
            replaced_match = match.replace(options.find_string, options.replace_with_string)
            if match != replaced_match:
                #The search string is found in the required fields so change it
                return_text = return_text.replace(match, replaced_match)
                changes += 1
    else:
        #We basically deal with two types of search and replace:
        #A standard string and a serialzed string.  In the latter, the new string length
        #needs computing
        
        #Easiest approach is to do two passes here.  First, we use a regex to find the special cases,
        #i.e. the serialized strings. Then we just do a basic find and replace on the rest.
        #FIXME: We don't attempt to differentiate between field values and field names themselves - 
        #this would seem to be an edge case in Wordpress dumps!
        
        #e.g. s:94:\"https://www.mydomain.com/blog/wp-content/plugins/podpress//images/vpreview_center.png\";
        serialized_string_regex = re.compile("""s:(\d+):\\\(?:"|')[^;]*?%s[^;]*?(?:"|');""" % options.find_string, re.DOTALL | re.UNICODE)
        serialized_matches = serialized_string_regex.finditer(source_text)
        
        for match in serialized_matches:
            #Get the old values
            match_text = match.group()
            match_str_length = match.group(1)
            
            #Do the f & r
            replaced_match = match_text.replace(options.find_string, options.replace_with_string)
            
            #Fixup the string lengths
            length_delta = len(match_text) - len(replaced_match)
            replaced_match = replaced_match.replace(match_str_length, unicode(int(match_str_length) - length_delta)) 
            
            #Find and replace the whole string
            return_text = return_text.replace(match_text, replaced_match)
            changes += 1
        
        #Now we've handled the tricky bit, just do a basic find and replace on the whole string text
        #There must be a way to do the count & replace
        remaining_changes = return_text.count(options.find_string)
        if remaining_changes:
            return_text = return_text.replace(options.find_string, options.replace_with_string)
            changes += remaining_changes
            
    if source_text == return_text:
        log ("Search string not found; no changes made")
    else:
        writeFile(options.out_file, return_text.encode(options.character_set))
        log ("%s changes made" % str(changes), 0)
    
    return
 
def main():
    options = parseargs()
    doReplace(options)

if __name__ == '__main__':
    main()

