class ViewModel
  @all = new ReactiveArray()
  @byId = (id) ->
    for vm in @all.list()
      return vm.vm if vm.id is id
    byTemplate = @byTemplate(id)
    return byTemplate[0] if byTemplate.length is 1
    undefined

  @byTemplate = (template) ->
    (vm.vm for vm in @all.list() when vm.template is template)

  @binds = {}
  @hasBind = (bindName) -> ViewModel.binds[bindName]?
  @addBind = (bindName, func) -> ViewModel.binds[bindName] = func

  @parseBind = VmHelper.parseBind

  constructor: (p1, p2) ->
    self = this
    _defaultComputation = null
    @_vm_id = ''

    @dispose = ->
      Session.set @_vm_id, undefined
      _defaultComputation.stop() if _defaultComputation
      thisId = @_vm_id
      self.parent()._vm_children.remove(self) if self.parent?()
      ViewModel.all.remove((vm) -> vm.vm._vm_id is thisId)
      self

    if p1 and p2
      @_vm_hasId = true
      @_vm_id = '_vm_' + p1
    else
      @_vm_id = '_vm_' + Math.random()

    obj = p2 || p1
    dependencies = {}
    values = {}
    initialValues = {}
    @_vm_properties = []
    dependenciesDelayed = {}
    valuesDelayed = {}
    @_vm_delayed = {}
    propertiesDelayed = []
    @_vm_children = new ReactiveArray()
    @children = (predicate) ->
      list = self._vm_children?.list()
      return list if not (predicate and list)

      test = null
      if _.isFunction(predicate)
        test = predicate
      else if _.isString(predicate)
        test = (vm) ->
          predicate is vm.templateInstance.view.name.substring("Template.".length)

      return (c for c in list when test(c))


    addRawProperty = (p, value, vm, values, dependencies) ->
      dep = dependencies[p] || (dependencies[p] = new Tracker.Dependency())
      vm[p] = (e) ->
        if VmHelper.isArray(e)
          values[p] = new ReactiveArray(e)
          dep.changed()
        else if arguments.length
          if VmHelper.isObject(values[p]) or values[p] isnt e
            values[p] = e
            dep.changed()
        else
          dep.depend()

        if values[p] instanceof ReactiveArray
          values[p].list()
        else
          values[p]
      if VmHelper.isArray(value)
        values[p] = new ReactiveArray(value)
      else
        values[p] = value

    @_vm_reservedWords = VmHelper.reservedWords

    addProperty = (p, value, vm) ->
      if _.has(values, p)
        vm[p] value
      else
        if p not in self._vm_reservedWords
          vm._vm_properties.push p
          initialValues[p] = value
        addRawProperty p, value, vm, values, dependencies

    @_vm_addDelayedProperty = (p, value, vm) ->
      propertiesDelayed.push p
      addRawProperty p, value, vm._vm_delayed, valuesDelayed, dependenciesDelayed

    addProperties = (propObj, that) ->
      for p of propObj
        value = propObj[p]
        if value instanceof Function or p in self._vm_reservedWords
          that[p] = value
        else
          addProperty p, value, that

    if VmHelper.isObject(obj)
      addProperties obj, @

    @_vm_addParent = (vm, template) ->
      if not vm.parent
        parentView = template.view.parentView
        t = null
        while parentView
          t = parentView.templateInstance() if parentView.templateInstance
          break if t?.viewmodel
          parentView = parentView.parentView
        vm.parent = -> t?.viewmodel
        if t?.viewmodel
          t.viewmodel._vm_children.push vm
        template.viewmodel = vm if not template.viewmodel

    @bind = (template) =>
      vm = @
      db = '[data-bind]:not([data-bound])'
      [container, dataBoundElements] = if VmHelper.isString(template)
        if Template[template]
          @_vm_addParent vm, Template[template]
          [Template[template], Template[template].$(db)]
        else
          [$(template), $(template).find(db)]
      else if VmHelper.isElement(template)
        [$(template), $(template).find(db)]
      else if template instanceof jQuery
        [template, template.find(db)]
      else
        @_vm_addParent vm, template
        [template, template.$(db)]

      vmForAll =
        vm: @
        id: @_vm_id.substring("_vm_".length)

      if template instanceof Blaze.TemplateInstance
        vmForAll.template = template.view.name.substring("Template.".length)

      ViewModel.all.push vmForAll

      if @_vm_hasId and container?.autorun
        _defaultComputation.stop() if _defaultComputation
        container.autorun (c) ->
          js = self._vm_toJS()
          return if c.firstRun
          Session.set self._vm_id, js

      dataBoundElements.each ->
        element = $(this)
        elementBind = VmHelper.parseBind element.data('bind')
        element.attr "data-bound", true
        for bindName of elementBind
          bindFunc = ViewModel.binds[bindName] || ViewModel.binds.default
          bindFunc
            vm: vm
            element: element
            elementBind: elementBind
            bindName: bindName
            property: elementBind[bindName]
            container: container
            autorun: (f) ->
              fun = (c) -> f(c)
              if container.autorun
                container.autorun fun
              else
                Tracker.autorun fun
      @

    @extend = (newObj) =>
      addProperties newObj, @
      objInSession = null
      Tracker.nonreactive ->
        objInSession = Session.get(self._vm_id)
      if @_vm_hasId and objInSession
        objMatch = {}
        objMatch[p] = objInSession[p] for p of newObj when _.has(objInSession, p)

        if not _.isEmpty(objMatch)
          self.fromJS objMatch
      @

    _addHelper = (name, template, that) ->
      obj = {}
      obj[name] = -> that[name]()
      if template instanceof Blaze.Template
        template.helpers obj
      else if template instanceof Blaze.TemplateInstance
        template.view.template.helpers obj
      else
        Template[template].helpers obj



    @addHelper = (helper, template) ->
      _addHelper helper, template, @
      @
    @addHelpers = (p1, p2) =>
      if p2
        helpers = p1
        template = p2
        if helpers instanceof Array
          for p in helpers when p not in @_vm_reservedWords
            _addHelper p, template, @
        else
          _addHelper helpers, template, @
      else
        template = p1
        for p of @ when p not in @_vm_reservedWords
          _addHelper p, template, @
      @

    @_vm_toJS = (includeFunctions) =>
      ret = {}
      if includeFunctions
        for p of @ when p not in @_vm_reservedWords and p not in propertiesDelayed
          ret[p] = @[p]()
      else
        for p in self._vm_properties when p not in propertiesDelayed
          value = @[p]()
          if value instanceof ReactiveArray
            ret[p] = value.array()
          else
            ret[p] = value

      for p in propertiesDelayed
        ret[p] = this._vm_delayed[p]()
      ret

    @toJS = (includeFunctions) =>
      ret = {}
      if includeFunctions
        for p of @ when p not in @_vm_reservedWords
          ret[p] = @[p]()
      else
        for p in self._vm_properties
          value = @[p]()
          if value instanceof ReactiveArray
            ret[p] = value.array()
          else
            ret[p] = value
      ret

    @fromJS = (obj) =>
      for p of values when typeof obj[p] isnt "undefined"
        value = obj[p]
        if value instanceof Array
          values[p] = new ReactiveArray(value)
        else
          values[p] = value
          valuesDelayed[p] = obj[p]

      for p of values when typeof obj[p] isnt "undefined"
        dependencies[p].changed()
        dependenciesDelayed[p].changed() if dependenciesDelayed[p]
      @

    @reset = ->
      for p in self._vm_properties
        if initialValues[p] instanceof Array
          values[p] = new ReactiveArray initialValues[p]
          valuesDelayed[p] = new ReactiveArray initialValues[p]
        else
          values[p] = initialValues[p]
          valuesDelayed[p] = initialValues[p]

      for p of values
        dependencies[p].changed()
        dependenciesDelayed[p].changed() if dependenciesDelayed[p]
      @

    if @_vm_hasId
      if Session.get(self._vm_id)
        self.fromJS Session.get(self._vm_id)
      else
        Session.setDefault self._vm_id, self._vm_toJS() if not Session.get(self._vm_id)?

      _defaultComputation = Tracker.autorun (c) ->
        obj = self._vm_toJS()
        if not c.firstRun
          Session.set self._vm_id, obj
