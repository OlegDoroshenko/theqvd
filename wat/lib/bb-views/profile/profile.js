Wat.Views.ProfileView = Wat.Views.DetailsView.extend({  
    setupOption: 'administrators',
    secondaryContainer: '.bb-setup',
    qvdObj: 'profile',
    
    setupOption: 'profile',
    
    limitByACLs: true,
    
    setActionAttribute: 'admin_attribute_view_set',
    setActionProperty: 'admin_property_view_set',
    
    viewKind: 'admin',
    
    breadcrumbs: {
        'screen': 'Home',
        'link': '#',
        'next': {
            'screen': 'Profile'
        }
    },
    
    initialize: function (params) {
        Wat.Views.MainView.prototype.initialize.apply(this, [params]);
        
        params.id = Wat.C.adminID;
        this.id = Wat.C.adminID;
        
        this.model = new Wat.Models.Admin(params);
        
        // The profile action to update current admin data is 'myadmin_update'
        this.model.setActionPrefix('myadmin');
        
        // Extend the common events
        this.extendEvents(this.eventsDetails);
        
        var templates = Wat.I.T.getTemplateList('profile', {qvdObj: this.qvdObj});
        
        Wat.A.getTemplates(templates, this.render, this); 
    },
    
    render: function () {        
        // Temporary hardcoded tenant name
        var tenantName = '*';
        
        this.template = _.template(
            Wat.TPL.profile, {
                cid: this.cid,
                login: Wat.C.login,
                language: Wat.C.language,
                block: Wat.C.block,
                tenantLanguage: Wat.C.tenantLanguage,
                tenantBlock: Wat.C.tenantBlock,
                tenantName: tenantName
            }
        );

        $('.bb-content').html(this.template);
        
        this.printBreadcrumbs(this.breadcrumbs, '');
        
        Wat.T.translateAndShow();
    },
    
    openEditElementDialog: function(e) {     
        this.dialogConf.title = $.i18n.t('Edit profile');
        Wat.Views.DetailsView.prototype.openEditElementDialog.apply(this, [e]);

        Wat.I.chosenConfiguration();
        Wat.I.chosenElement('select[name="language"]', 'single100');
        Wat.I.chosenElement('select[name="block"]', 'single100');
    },
    
    updateElement: function (dialog) {
        var valid = Wat.Views.DetailsView.prototype.updateElement.apply(this, [dialog]);
        
        if (!valid) {
            return;
        }
        
        var filters = {"id": this.id};
        var arguments = {};
        
        var context = $('.' + this.cid + '.editor-container');

        // If change password is checked
        if (context.find('input.js-change-password').is(':checked')) {
            var password = context.find('input[name="password"]').val();
            var password2 = context.find('input[name="password2"]').val();
            if (password && password2 && password == password2) {
                arguments['password'] = password;
            }
        }
        
        // Set language
        var language = context.find('select[name="language"]').val();
        arguments['language'] = language;  
        
        // Set block size
        var block = context.find('select[name="block"]').val();
        arguments['block'] = block;
        
        // Store new language to make things after update
        this.newLanguage = language;
        this.newBlock = block;
        
        this.updateModel(arguments, filters, this.afterUpdateElement);
    },
    
    afterUpdateElement: function (that) {
        // If change is made succesfully check new language to ender again and translate
        if (that.retrievedData.status == STATUS_SUCCESS) {
            if (Wat.C.language != that.newLanguage) {
                Wat.C.language = that.newLanguage;
            }
            if (Wat.C.block != that.newBlock) {
                Wat.C.block = that.newBlock;
            }
            that.render();
            Wat.T.initTranslate();
        }
    }
});