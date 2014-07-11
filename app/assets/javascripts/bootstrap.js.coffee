$(document).on 'ready page:load', ->
  $(".chosen-select").chosen()

  $("a[rel~=popover], .has-popover").popover()
  $("a[rel~=tooltip], .has-tooltip").tooltip()

  $("span.pie").peity "pie",
    fill: ["#3498db", "#eee"]

  # timeline
  options =
    placement: (context, source) ->
      position = $(source).position()
      # the timeline is max ~550px in height
      if position.top - 280 < 0 
        # rearrange to bottom
        # otherwise it is cut off the top
        "bottom"
      else
        "right"

    trigger: "click"

  $(".timeline-button").popover options

  # close popover when clicking outside of current popover
  $(document).on "mousedown", (e) ->
    $(".has-popover, .timeline-button").each ->
      #the 'is' for buttons that trigger popups
      #the 'has' for icons within a button that triggers a popup
      $(this).popover "hide"  if not $(this).is(e.target) and $(this).has(e.target).length is 0 and $(".popover").has(e.target).length is 0
