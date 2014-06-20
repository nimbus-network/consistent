
diff = (a, b)->
  if a.length > b.length
    # A character was deleted
    for i in [0..b.length]
      if a[i] != b[i]
        return { pos: i, char: '\b' }

    return { pos: i, char: '\b' }
  else
    for i in [0..a.length]
      if a[i] != b[i]
        return { pos: i, char: b[i] }

    return { pos: i, char: b[i] }

observe = (text, list)->
  lastValue = text.value

  text.oninput = ->
    { pos, char } = diff lastValue, text.value

    lastValue = text.value

    if char == '\b'
      list.remove pos
    else
      list.insert char, pos

text1 = document.getElementById 'text1'
text2 = document.getElementById 'text2'
list1 = new List()
list2 = new List()

observe text1, list1
observe text2, list2

document.getElementById('sync1').onclick = ->
  list2.applyEvents list1.events()
  text2.value = list2.items().join ''

document.getElementById('sync2').onclick = ->
  list1.applyEvents list2.events()
  text1.value = list1.items().join ''

