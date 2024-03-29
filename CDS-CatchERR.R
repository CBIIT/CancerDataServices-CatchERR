#!/usr/bin/env Rscript

#Cancer Data Services - CatchERR.R

#This script will take a CDS metadata manifest file and try to blindly fix the most common errors before the validation step.

##################
#
# USAGE
#
##################

#Run the following command in a terminal where R is installed for help.

#Rscript --vanilla CDS-CatchERR.R --help


##################
#
# Env. Setup
#
##################

#List of needed packages
list_of_packages=c("readr","openxlsx","dplyr","tidyr","stringi","readxl","janitor","optparse","tools")

#Based on the packages that are present, install ones that are required.
new.packages <- list_of_packages[!(list_of_packages %in% installed.packages()[,"Package"])]
suppressMessages(if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org"))

#Load libraries.
suppressMessages(library(readr,verbose = F))
suppressMessages(library(readxl,verbose = F))
suppressMessages(library(openxlsx, verbose = F))
suppressMessages(library(dplyr, verbose = F))
suppressMessages(library(tidyr, verbose = F))
suppressMessages(library(stringi,verbose = F))
suppressMessages(library(janitor,verbose = F))
suppressMessages(library(optparse,verbose = F))
suppressMessages(library(tools,verbose = F))


#remove objects that are no longer used.
rm(list_of_packages)
rm(new.packages)


##################
#
# Arg parse
#
##################

#Option list for arg parse
option_list = list(
  make_option(c("-f", "--file"), type="character", default=NULL, 
              help="dataset file (.xlsx, .tsv, .csv)", metavar="character"),
  make_option(c("-t", "--template"), type="character", default=NULL, 
              help="dataset template file, CDS_submission_metadata_template.xlsx", metavar="character")
)

#create list of options and values for file input
opt_parser = OptionParser(option_list=option_list, description = "\nCDS-CatchERR v2.0.8")
opt = parse_args(opt_parser)

#If no options are presented, return --help, stop and print the following message.
if (is.null(opt$file)&is.null(opt$template)){
  print_help(opt_parser)
  cat("Please supply both the input file (-f) and template file (-t), CDS_submission_metadata_template.xlsx.\n\n")
  suppressMessages(stop(call.=FALSE))
}


#Data file pathway
file_path=file_path_as_absolute(opt$file)

#Template file pathway
template_path=file_path_as_absolute(opt$template)

###########
#
# File name rework
#
###########

#Rework the file path to obtain a file extension.
file_name=stri_reverse(stri_split_fixed(stri_reverse(basename(file_path)),pattern = ".", n=2)[[1]][2])
ext=tolower(stri_reverse(stri_split_fixed(stri_reverse(basename(file_path)),pattern = ".", n=2)[[1]][1]))
path=paste(dirname(file_path),"/",sep = "")

#Output file name based on input file name and date/time stamped.
output_file=paste(file_name,
                  "_CatchERR",
                  stri_replace_all_fixed(
                    str = Sys.Date(),
                    pattern = "-",
                    replacement = ""),
                  sep="")

output_file_index=paste(file_name,
                  "_index",
                  stri_replace_all_fixed(
                    str = Sys.Date(),
                    pattern = "-",
                    replacement = ""),
                  sep="")


NA_bank=c("NA","na","N/A","n/a","")

#Read in file with trim_ws=TRUE
if (ext == "tsv"){
  df=suppressMessages(read_tsv(file = file_path, trim_ws = TRUE, na=NA_bank, guess_max = 1000000, col_types = cols(.default = col_character())))
}else if (ext == "csv"){
  df=suppressMessages(read_csv(file = file_path, trim_ws = TRUE, na=NA_bank, guess_max = 1000000, col_types = cols(.default = col_character())))
}else if (ext == "xlsx"){
  df=suppressMessages(read_xlsx(path = file_path, trim_ws = TRUE, na=NA_bank, sheet = "Metadata", guess_max = 1000000, col_types = "text"))
}else{
  stop("\n\nERROR: Please submit a data file that is in either xlsx, tsv or csv format.\n\n")
}


#############
#
# Data frame manipulation
#
#############

#Start write out for log file
sink(paste(path,output_file,".txt",sep = ""))

cat("\n\nThe following columns have controlled vocabulary on the 'Terms and Value Sets' page of the template file. If the values present do not match, they will noted and in some cases fixed:\n----------\n")


df_tavs=suppressMessages(read_xlsx(path = template_path, sheet = "Terms and Value Sets"))
df_tavs=remove_empty(df_tavs,c('rows','cols'))

#Pull out the positions where the value set names are located
VSN=grep(pattern = FALSE, x = is.na(df_tavs$`Value Set Name`))

df_all_terms=list()

#for each instance of a value_set_name, note the position on the Terms and Value Sets page, create a list for each with all accepted values.
for (x in 1:length(VSN)){
  if (!is.na(VSN[x+1])){
    df_all_terms[as.character(df_tavs[VSN[x],1])] = as.vector(df_tavs[VSN[x]:(VSN[x+1]-1),3])
    
  }else{
    df_all_terms[as.character(df_tavs[VSN[x],1])] = as.vector(df_tavs[VSN[x]:dim(df_tavs)[1],3])
  }
}

#Enumerated Array properties
enum_arrays=c('therapeutic_agents',"treatment_type","study_data_types","morphology","primary_site","race")

#Use the list of all accepted values for each value_set_name, and compare that against the Metadata page and determine if the values, if present, match the accepted terms.
for (value_set_name in names(df_all_terms)){
  if (value_set_name %in% enum_arrays){
    
    #Sort each array before checks
    for (array_value_pos in 1:length(df[value_set_name][[1]])){
      array_value=df[value_set_name][[1]][array_value_pos]
      if (grepl(pattern = ";", array_value)){
        
        #alphabetize array
        array_value=paste(sort(trimws(unique(stri_split_fixed(str = array_value, pattern = ";")[[1]]))), collapse = ";")
        df[value_set_name][[1]][array_value_pos]=array_value
      }
    }
    
    #Set up to find values that are not in the expected permissible value (PV) list
    unique_values=unique(df[value_set_name][[1]])
    unique_values=unique(trimws(unlist(stri_split_fixed(str = unique_values,pattern = ";"))))
    unique_values=unique_values[!is.na(unique_values)]
    if (length(unique_values)>0){
      if (!all(unique_values%in%df_all_terms[value_set_name][[1]])){
        for (x in 1:length(unique_values)){
          check_value=unique_values[x]
          if (!is.na(check_value)){
            if (!as.character(check_value)%in%df_all_terms[value_set_name][[1]]){
              cat(paste("ERROR: ",value_set_name," property contains a value that is not recognized: ", check_value,"\n",sep = ""))
              
              #NEW ADDITION to push the most correct value into the proper case
              if (tolower(as.character(check_value))%in%tolower(df_all_terms[value_set_name][[1]])){
                
                #determine the correct PV
                pv_pos=grep(pattern = TRUE, x = tolower(df_all_terms[value_set_name][[1]])%in%tolower(as.character(check_value)))
                
                #find all the value positions for the property with wrong value
                value_positions=grep(pattern = as.character(check_value) , x = df[value_set_name][[1]])
                
                #create a filter to remove positions that are erroneously selected and either find only values that are the whole string or the string in part of an array list.
                for (value_pos in value_positions){
                  previous_value=df[value_pos,value_set_name][[1]]
                  replacement_value=df_all_terms[value_set_name][[1]][pv_pos]
                  if (nchar(previous_value)!=nchar(replacement_value)){
                    array_pattern=c(paste(replacement_value,";",sep = ""),paste(";",replacement_value,sep = ""))
                    array_pos=grep(pattern = tolower(paste(array_pattern,collapse = "|")), x = tolower(previous_value))
                    if (length(array_pos)==0){
                      value_positions=value_positions[!(value_positions %in% value_pos)]
                    }
                  }
                }
                
                #create dataframe to capture values changed as to not overload with lines
                prev_repl_df=tibble(previous_value_col=NA, replacement_value_col=NA)
                prev_repl_df_add=tibble(previous_value_col=NA, replacement_value_col=NA)
                prev_repl_df=prev_repl_df[0,]
                
                #for each position, change the value in the array.
                for (value_pos in value_positions){
                  previous_value=df[value_pos,value_set_name][[1]]
                  replacement_value=df_all_terms[value_set_name][[1]][pv_pos]
                  df[value_pos,value_set_name]<-stri_replace_all_fixed(str =previous_value, pattern = as.character(check_value), replacement = replacement_value)
                  
                  prev_repl_df_add$previous_value_col=previous_value
                  prev_repl_df_add$replacement_value_col=replacement_value
                  
                  prev_repl_df=unique(rbind(prev_repl_df,prev_repl_df_add))
                }
                
                for ( prdf in 1:dim(prev_repl_df)[1]){
                  cat(paste("\tThe value in ",value_set_name,", was changed: ", prev_repl_df$previous_value_col[prdf]," ---> ",prev_repl_df$replacement_value_col[prdf],"\n",sep = ""))
                }
              }
            }
          }
        }
      }else{
        cat(paste("PASS:",value_set_name,"property contains all valid values.\n"))
      }
    }
  }else if (value_set_name%in%colnames(df)){
    unique_values=unique(df[value_set_name][[1]])
    unique_values=unique_values[!is.na(unique_values)]
    if (length(unique_values)>0){
      if (!all(unique_values%in%df_all_terms[value_set_name][[1]])){
        for (x in 1:length(unique_values)){
          check_value=unique_values[x]
          if (!is.na(check_value)){
            if (!as.character(check_value)%in%df_all_terms[value_set_name][[1]]){
              cat(paste("ERROR: ",value_set_name," property contains a value that is not recognized: ", check_value,"\n",sep = ""))
              
              #NEW ADDITION to push the most correct value into the proper case
              if (tolower(as.character(check_value))%in%tolower(df_all_terms[value_set_name][[1]])){
                pv_pos=grep(pattern = TRUE, x = tolower(df_all_terms[value_set_name][[1]])%in%tolower(as.character(check_value)))
                value_pos=grep(pattern = TRUE, x = df[value_set_name][[1]]%in%as.character(check_value))
                df[value_pos,value_set_name]<-df_all_terms[value_set_name][[1]][pv_pos]
                cat(paste("\tThe value in ",value_set_name," was changed:\n\t", check_value," ---> ",df_all_terms[value_set_name][[1]][pv_pos],"\n",sep = ""))
              }
            }
          }
        }
      }else{
        cat(paste("PASS:",value_set_name,"property contains all valid values.\n"))
      }
    }
  }
}

##############
#
# Check and replace for non-UTF-8 characters
#
##############

cat("\n\nCertain characters do not handle being transformed into certain file types, due to this, the following characters were changed.\n----------\n")

#initialize table and then populate the key value pairs for the value that is present and what it needs to be converted to.
df_translations=tibble(value="",translation="")[0,]

#Expression to expand further pairs, copy the following line and add the new value pair.
df_translations=rbind(df_translations,tibble(value="™",translation="(TM)"))




#Grep through column and rows looking for values to change.
for (value in 1:dim(df_translations)[1]){
  df_value=df_translations[value,"value"]
  df_translate=df_translations[value,"translation"]
  colnums=grep(pattern = df_value, df)
  for (colnum in colnums){
    rownums=grep(pattern = df_value, df[,colnum][[1]])
    for (rownum in rownums){
      df[rownum,colnum]=stri_replace_all_fixed(str = df[rownum,colnum], pattern = df_value, replacement = df_translate)
    }
    cat(paste("\nWARNING: The following property, ",colnames(df[,colnum]),", contain values, ",df_value,", that can create issues when transforming, these were changed to : ",df_translate,"\n", sep = ""))
  }
}


##############
#
# ACL pattern check
#
##############

cat("\n\nThe value for ACL will be check to determine it follows the required structure, ['.*'].\n----------\n")

acl_check=unique(df$acl)

if (length(acl_check)>1){
  cat("ERROR: There is more than one ACL associated with this study and submission templte. Please only submit one ACL and corresponding data to a submission template.\n")
}else if(length(acl_check)==1){
  if (is.na(acl_check)){
    cat("ERROR: Please submit an ACL value to the 'acl' property.\n")
  }else if (!is.na(acl_check)){
    acl_test=grepl(pattern = "\\[\\'.*\\'\\]" , x= acl_check)
    if (!acl_test){
      acl_fix=paste("['",acl_check,"']", sep="")
      cat("The following ACL does not match the required structure, it will be changed:\n\t\t", acl_check, " ---> ", acl_fix,"\n",sep = "")
      df$acl=acl_fix
    }else if (acl_test){
      cat("The following ACL matches the required structure:\n\t\t", acl_check,"\n",sep = "")
    }
  }
}else{
  cat("ERROR: Something is wrong with the ACL value submitted in the acl property.\n")
}


##############
#
# Fix url paths
#
##############

cat("\n\nCheck the following url columns (file_url_in_cds), to make sure the full file url is present and fix entries that are not:\n----------")

#Fix urls if the url does not contain the file name but only the base url
#If full file path is in the url
for (bucket_loc in 1:dim(df)[1]){
  bucket_url=df$file_url_in_cds[bucket_loc]
  bucket_file=df$file_name[bucket_loc]
  
  #skip if bucket_url is NA (no associated url for file)
  if (!is.na(bucket_url)){
    #see if the file name is found in the bucket_url
    file_name=basename(bucket_url)
    if (bucket_file!=file_name){
      #the file url has to be reworked to include the file with the base directory.
        if (substr(bucket_url,start = nchar(bucket_url),stop = nchar(bucket_url))=="/"){
          #fix the 'file_url_in_cds' section to have the full file location
          bucket_url_change=paste(bucket_url,bucket_file,sep = "")
          #double check changes made
          file_name=basename(bucket_url_change)
          if (bucket_file!=file_name){
            cat(paste("\nERROR: There is an unresolvable issue with the file url for file: ",bucket_file,sep = ""))
          }else{
            #if file name is still found, then change the url
            df$file_url_in_cds[bucket_loc]=bucket_url_change
            cat(paste("\nWARNING: The file location for the file, ", bucket_file,", has been changed:\n\t", bucket_url, " ---> ", bucket_url_change,sep = ""))
          }
        }else{
          #fix the 'file_url_in_cds' section to have the full file location
          bucket_url_change=paste(bucket_url,"/",bucket_file,sep = "")
          #double check changes made
          file_name=basename(bucket_url_change)
          if (bucket_file!=file_name){
            cat(paste("\nERROR: There is an unresolvable issue with the file url for file: ",bucket_file,sep = ""))
          }else{
            #if file name is still found, then change the url
            df$file_url_in_cds[bucket_loc]=bucket_url_change
            cat(paste("\nWARNING: The file location for the file, ", bucket_file,", has been changed:\n\t", bucket_url, " ---> ", bucket_url_change,sep = ""))
          }
        }
      }
    }
  }


#close log file write out
sink()


###############
#
# Assign guids to files
#
###############

cat("\nEach unique file will now have a guid assigned to it.\nguid creation: \n")

#Function to determine if operating system is OS is mac or linux, to run the UUID generation.
get_os <- function(){
  sysinf <- Sys.info()
  if (!is.null(sysinf)){
    os <- sysinf['sysname']
    if (os == 'Darwin')
      os <- "osx"
  } else { ## mystery machine
    os <- .Platform$OS.type
    if (grepl("^darwin", R.version$os))
      os <- "osx"
    if (grepl("linux-gnu", R.version$os))
      os <- "linux"
  }
  tolower(os)
}

if ("guid" %in% colnames(df)){
  df_index=df%>%
    select(guid ,file_url_in_cds, file_name, file_size, md5sum)
}else{
  df_index=df%>%
    select(file_url_in_cds, file_name, file_size, md5sum)%>%
    mutate(guid=NA)
}

df_index=unique(df_index)
#For each unique file, apply a uuid to the guid column. There is logic to handle this in both OSx and Linux, as the UUID call is different from R to the console.
pb=txtProgressBar(min=0,max=dim(df_index)[1],style = 3)

for (x in 1:dim(df_index)[1]){
  setTxtProgressBar(pb,x)
  if (is.na(df_index$guid[x])){
    if (get_os()=="osx"){
      uuid=tolower(system(command = "uuidgen", intern = T))
    }else{
      uuid=system(command = "uuid", intern = T)
    }
    #Take the uuids in the guid column and paste on the 'dg.4DFC/' prefix to create guids for all the files.
    df_index$guid[x]=paste("dg.4DFC/",uuid,sep = "")
  }
}

df=suppressMessages(left_join(df,df_index,multiple="all", c('file_name', 'file_size', 'md5sum', 'file_url_in_cds')))

if ('guid.x' %in% colnames(df)){
  df$guid=NA
  
  for (row in 1:dim(df)[1]){
    #if there is at least one non-NA value
    if (!is.na(df$guid.x[row]) | !is.na(df$guid.y[row])){
      #if there are two non-NA values
      if (!is.na(df$guid.x[row]) & !is.na(df$guid.y[row])){
        if (df$guid.x[row] == df$guid.y[row]){
          df$guid[row]=df$guid.x[row]
        }else{
          cat("ERROR: The following row,", row, ", has two GUID values and will default to the original value from the supplied data frame.", sep = "")
          df$guid[row]=df$guid.x[row]
        }
      }else{
        if (!is.na(df$guid.x[row]) & is.na(df$guid.y[row])){
          df$guid[row]=df$guid.x[row]
        }else if (is.na(df$guid.x[row]) & !is.na(df$guid.y[row])){
          df$guid[row]=df$guid.y[row]
        }
      }
    }else if (is.na(df$guid.x[row]) & is.na(df$guid.y[row])){
      cat("ERROR: The following row,", row, ", did not receieve a GUID due to an unknown error.", sep = "")
    }
  }
  df=df%>%
    select(-guid.x,-guid.y)
}


df_for_index=df%>%
  mutate(size=file_size, md5=md5sum, url=file_url_in_cds, authz=acl)%>%
  select(guid, md5, size, acl, authz, url, everything())

df_for_index$authz=stri_replace_all_fixed(str = df_for_index$authz[1], pattern = "['", replacement = "['/programs/")


###############
#
# Write out CatchERR file
#
# This was done as a check point before the roll up that is required in index-able files now.
# This will save time if something fails, as this will now have the guids for the files and can then be used as the next input file for CatchERR or Submission_ValidationR.
#
###############

#Write out file
if (ext == "tsv"){
  suppressMessages(write_tsv(df, file = paste(path,output_file,".tsv",sep = ""), na=""))
}else if (ext == "csv"){
  suppressMessages(write_csv(df, file = paste(path,output_file,".csv",sep = ""), na=""))
}else if (ext == "xlsx"){
  wb=openxlsx::loadWorkbook(file = file_path)
  openxlsx::deleteData(wb, sheet = "Metadata",rows = 1:(dim(df)[1]+1),cols=1:(dim(df)[2]+1),gridExpand = TRUE)
  openxlsx::writeData(wb=wb, sheet="Metadata", df)
  openxlsx::saveWorkbook(wb = wb,file = paste(path,output_file,".xlsx",sep = ""), overwrite = T)
}



###############
#
# Roll Up
#
###############

sink(paste(path,output_file,".txt",sep = ""),append = TRUE)
cat("\n\nThis section will display which file guids were duplicated in the flatten form and thus rolled up to make it an acceptable Velsera submission:\n----------")
sink()

#For some submissions that contain files that have multiple samples per file, thus multiple lines per file, they need to be rolled up to better work with SBG/Velsera ingestion.

df_for_index_filtered_new=df_for_index[0,]

#Progress bar for roll up
pb=txtProgressBar(min=0,max=length(unique(df_for_index$guid)),style = 3)
x=0
cat("\nCreating Roll Ups for specific files: \n", sep = "")

for(uguid in unique(df_for_index$guid)){
  setTxtProgressBar(pb,x)
  x=x+1
  df_for_index_filtered=filter(df_for_index, guid==uguid)
  if (dim(df_for_index_filtered)[1]!=1){
    for (colnum in 1:dim(df_for_index_filtered)[2]){
      col_vals=unique(df_for_index_filtered[,colnum])[[1]]
      if (any(!is.na(col_vals))){
        col_vals=paste(col_vals,collapse = ";")
        df_for_index_filtered[,colnum]<- col_vals
      }
    }
    #Start write out for log file again
    sink(paste(path,output_file,".txt",sep = ""),append = TRUE)
    cat("\nWARNING: The GUID, ", uguid, ", does not resolve into one row by Velsera standards. **UPDATING TO ROLL UP FORMAT**",sep = "")
    sink()
    df_for_index_filtered=unique(df_for_index_filtered)
    
    df_for_index_filtered_new=rbind(df_for_index_filtered_new,df_for_index_filtered)
    
  }else{
    df_for_index_filtered_new=rbind(df_for_index_filtered_new,df_for_index_filtered)
  }
}

df_for_index=unique(df_for_index_filtered_new)


################
#
# File_type appender for SBG/Velsera
#
################

# Velsera does not use the file_type property to determine the file type, but instead pulls
# the extension off of the file_name property. To ensure that the correct file_type is
# obtained, this section will check to see if the extension matches the file_type that is
# noted and if it does not have that extension, it is appended as a suffix to the file_name
# value.

#Create a data frame to summarize the changes made, to be printed out
df_ext_change=data.frame(pre=NA,post=NA)
df_ext_change_add=df_ext_change
df_ext_change=df_ext_change[-1,]


sink(paste(path,output_file,".txt",sep = ""),append = TRUE)

cat("\n\nThis section will display all changes that were made to the file_name value for each file to ensure that the file extension matches the 'file_type' column to ensure correct ETL in Velsera:\n----------")

for (inv_file_guid in 1:length(unique(df_for_index$guid))){
  gz_flag=FALSE
  ext_change=FALSE
  file_name=df_for_index$file_name[inv_file_guid]
  test_ext=tolower(file_ext(file_name))
  exp_ext=tolower(df_for_index$file_type[inv_file_guid])
  
  #check for gzip, fix the filename, note it and then give the next extension
  if( test_ext == 'gz'){
    file_name_gz=file_path_sans_ext(file_name)
    gz_flag=TRUE
    test_ext=tolower(file_ext(file_name_gz))
    if ( exp_ext == paste(test_ext,".gz",sep = "")){
      test_ext=paste(test_ext,".gz",sep = "")
    }
  }
  
  if (test_ext!=exp_ext){
    ext_change=TRUE
    
    #set the file type to the new file extension
    test_ext_change=exp_ext
    
    # an example where the file type is a longer name (fastq) of the actual extension (fq)
    # but the extension (fq) is recognized and fine as a shorten term.
    # Since this situation is acceptable, the ext_change flag is set to FALSE to no longer
    # change the file ext.
    if(all(exp_ext == 'fastq' & test_ext == 'fq')){
      ext_change=FALSE
    }
    
    if(all(exp_ext == 'tiff' & test_ext == 'tif')){
      ext_change=FALSE
    }
    
    # an example of where the file type (gvcf) is more specific than what the extension
    # would pull (vcf), because the file name is setup differently (it should be 
    # filename.gvcf.gz, but instead it is filename.g.vcf.gz)
    if( all(exp_ext == 'gvcf' & test_ext=="vcf")){
      test_ext_change="gvcf"
    }
    
    # if the ext_change is TRUE, then we have determined the file ext still needs 
    # to be changed.
    if (ext_change==TRUE){
      cat("\nWARNING: There is an unexpected file type for, ",file_name, ", and will be fixed:\n\t",test_ext," ---> ",exp_ext, sep="")
      
      #Update general changes made
      df_ext_change_add$pre=test_ext
      df_ext_change_add$post=exp_ext
      
      df_ext_change=rbind(df_ext_change,df_ext_change_add)
      df_ext_change=unique(df_ext_change)
      
      # if the gz_flag is true, then the gz needs to be put back on after the 
      # new ext is added.
      if (gz_flag==TRUE){
        file_name=paste(file_name_gz,'.',test_ext_change,".gz",sep = "")
        df_for_index$file_name[inv_file_guid]=file_name
        cat("\n\t",file_name,sep = "")
      }else{
        file_name=paste(file_name,'.',test_ext_change,sep = "")
        df_for_index$file_name[inv_file_guid]=file_name
        cat("\n\t",file_name,sep = "")
      }
    }
  }
}

cat("\n\n---------\nThe following overview of changes were made to the files, where the original value had the second value added onto the end.\n---------")

df_ext_change=arrange(df_ext_change, pre, post)
df_ext_change=remove_empty(dat = df_ext_change, which = c("rows","cols"))


if (dim(df_ext_change)[1]!=0){
  for (ext_pos in 1:dim(df_ext_change)[1]){
    cat("\n\t",df_ext_change$pre[ext_pos]," ---> ",df_ext_change$post[ext_pos],sep = "")
  }
}


sink()


#################
#
# Double file names
#
#################

#This section deals with the inability for SBG/Velsera to handle file_name values that are the same.

df_double_name=filter(count(group_by(df_for_index, file_name)), n>1)

df_file_url=select(df_for_index[(df_for_index$file_name %in% df_double_name$file_name),], file_name, file_url_in_cds)

df_file_url=mutate(df_file_url,file_name_old=file_name, file_name=stri_reverse(file_url_in_cds))%>%
  separate(file_name, c("file","upper_dir","other_dir"), sep = "/", extra = "merge")%>%
  mutate(file_name=paste(file,upper_dir,sep = "_"), file_name=stri_reverse(file_name))%>%
  select(-other_dir,-file,-upper_dir)

for (x in 1:dim(df_file_url)[1]){
  df_for_index$file_name[df_for_index$file_url_in_cds %in% df_file_url$file_url_in_cds[x]]<-df_file_url$file_name[x]
}

sink(paste(path,output_file,".txt",sep = ""),append = TRUE)

cat("\n\nThis section will display all changes that were made to the file_name value for each file to ensure that the file_name is unique among all files to ensure correct ETL in Velsera:\n----------")

df_file_url=arrange(df_file_url, file_name_old, file_name)
df_file_url=remove_empty(dat = df_file_url, which = c("rows","cols"))


if (dim(df_file_url)[1]!=0){
  for (x in 1:dim(df_file_url)[1]){
    cat("\n\t",df_file_url$file_name_old[x]," ---> ",df_file_url$file_name[x],sep = "")
  }
}

df_double_name=filter(count(group_by(df_for_index, file_name)), n>1)

if (dim(df_double_name)[1]!=0){
  cat("\n$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$\n\nERROR: Even after creating new names from the combination of the file_name and it's parent directory, there are still file_name values that are the same.\n\n$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$\n")
}


sink()



###############
#
# Write out
#
###############

#Write out index-able file

write_tsv(x = df_for_index, file = paste(path,output_file_index,".tsv",sep = ""),na="")


cat(paste("\n\nProcess Complete.\n\nThe output file can be found here: ",path,"\n\n",sep = "")) 
