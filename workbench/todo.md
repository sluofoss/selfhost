For each of the following todo, please change them to checkbox - [x] if completed. if any form of answer is required, please create a new .md file with the question number and short question summary as file name and answer as content. if there are any follow up tasks, please add them as incomplete sublist task under the original question here in this file.

1. monitor usage of class c transaction in b2 during period of no upload and just geo data viewing
   1. if the cost does explode then consider migrating to juicefs
2. got logical explanation of pgsql size in workbench but may need to further configure that.
3. consider thumbnail cache and the ratio of that to class c transaction
4. consider if one should reduce the size of thumbnail, 3:1 ratio seems unfeasible to keep on oci block volume, will this ratio be the same as more file comes in? how much further can we reduce this? 
   1. please model the thumbnail growth and what does a cleanup policy mean in terms of user experience and cost. 
5. did i ask how many current things minor things are stored to b2 and what are the associated cost when rebuilding the instance? please create a separate .md script under the workbench folder to figure this out.
6. whats the cost of storing that pgsql into b2? how often is this updated and pushed to b2? 
7. create a separate .md file under workbench trying to analyse the need to use authelia to protect the instance, how will it impact multi user experience on immich, and how we can implement this.
8. create a separate .md file under workbench trying to figure out what to update in opentofu to essentially force all https (and perhaps ssh?) traffic to come from cloudflare into the oci reserved ip address such that we can reduce the attack surface on the instance. and give cost benefit analysis on this approach. (currently the ssh is allowed from anywhere but protected by oci pem file, and the https and http should also be allowed from anywhere according to my understanding).