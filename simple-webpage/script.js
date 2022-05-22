
$("#cat_image").hide();

$("#submit").click(function(){
   //$("#cat_image").show();
   if($("#username").val()!="") {
        $("#error").html("");
        $("#need_a_hug").html("Yes, you need a HUG <h2>" + $("#username").val().toUpperCase() + "</h2>");
    }
    else {
        $("#error").html("Your name is required.");
        $("#need_a_hug").html("");
    }
});

