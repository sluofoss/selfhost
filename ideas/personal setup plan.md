I need your help to organise my requirements first before like further deep down diving into building up a viable plan and set up so currently my requirement is that I want to be able to listen to medias like essentially like a musics or and or like a videos on my phone via a sort of like download one sort of thing or like only sync when there's any sort of difference between what's being stored on my phone and on my server so that's the first thing the second thing is that I need to be able to have a centralised system that's sort of like essentially serves allows like enables access and indexings of all these files such that I can browse them uniformly so this I guess can already be achieved via the file browser docker container within the dev tools but I'm not sure how heavy it is in terms of indexing on B-2 cost is because the class c transaction is just expensive

The third thing is that I want to be able to minimise the cost of having a bunch of different services on my server because having I feel like what you suggested a subsonic API like Navy drone hosted on my server on top of file explorer on top of something poteny like seafile pro something potentially like next clouds rclone It's just too many duplicates of too many similar services and it's you know just a headache to manage.



---

feedback:

1. lets keep obsidian livesync(couchdb) + seafile pro. (i used syncthing before and obsidian plugin between pc and mobile just causes way too much issues.)
2. now, for all the periodic backup because seafile doesnt seem to have a good self recovery or reconstruction. it is now crucial to have the ability to be notified on any backup failure via sms/WhatsApp such that I can inspect this immediately and kick start remediation. what are some free way to do this easily within the oci stack? currently Grafana is not properly utilized. (no source is active rightn  now ) (I dont get discord notif on my phone, nor email, i guess i can start using telegram for this purpose?)
3. another major concern is authentication safety and zero day attach on the server in general. Previously i was pushing back on  uusing authelia due tot  dpmt want to create additional login aftinfront of existing immich login  and potential file sharing issue within immich,i=aka i dont want to share a fiimage and require other people to log in to see it but at the same time i still want to keep it sec. ive found this on the web https://github.com/alangrainger/immich-public-proxy and  esentially with this we can hanow actually consider adding in authelia without causin g any issu(but have we consider the potential impact of this on othrer servies like obsidian live sync coder server grafana and traefik and potentially seafle? ) is authelia the best within multi user setting or is something like authentik or something else that is equally lightweight suitable for this purpose? think of ease of integration, maintenance complexity, memory and resource usage, and cost.

  - there is a n uncommitted file under trefik dynamic alled routers. i think that cant be committed but just need to have the actual domain wireplaced with a dtemplate variable 



  - would it be helpful to have a mounted volume for the vscode container that is backed up to backblaze? this essentially will contain a lot of  small changes ing files i a come from npm and stuff. so perhaps it is better to wait after seafile implementation. what do you think? #wait-until-seafile

- 1 issue i just found about about immich is that as mentioned in https://www.reddit.com/r/immich/comments/1n4hyso/large_video_uploads_stalling_problem_solved/ cloudflare free has a limit on file upload size of 300mb. so all my large video uploads from android are getting screwed. what are some ways to circumvent this? the mentioned soln was intended for local home deployment and because this is for cloud, i'm not sure how different it is. can you create a ticket to investigate this and find a solution?