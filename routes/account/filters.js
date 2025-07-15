'use strict';

const express = require('express');
const router = new express.Router();
const Joi = require('joi');
const apiClient = require('../../lib/api-client');

const filterBaseSchema = {
  name: Joi.string().empty('').trim().max(100).label('Name'),

  query_from: Joi.string().empty('').trim().max(100).label('From'),
  query_to: Joi.string().empty('').trim().max(100).label('To'),
  query_subject: Joi.string().empty('').trim().max(100).label('Subject'),
  query_text: Joi.string().empty('').trim().max(100).label('Includes'),
  query_listId: Joi.string().empty('').trim().max(100).label('List-ID'),
  query_haYes: Joi.boolean().optional().label('Has attachments'),
  query_haNo: Joi.boolean().optional().label('Does not have attachments'),
  query_sizeType: Joi.number().label('Size type'),
  query_sizeValue: Joi.number().empty('').label('Size'),
  query_sizeUnit: Joi.string().valid('MB', 'kB', 'B').label('Size unit'),

  action_seenYes: Joi.boolean().optional().label('Mark as seen'),
  action_flagYes: Joi.boolean().optional().label('Flag it'),
  action_deleteYes: Joi.boolean().optional().label('Delete'),
  action_spamYes: Joi.boolean().optional().label('Mark as spam'),
  action_spamNo: Joi.boolean().optional().label('Do not mark as spam'),

  action_targets: Joi.array()
    .items(
      Joi.string().email().trim().empty(''),
      Joi.string()
        .trim()
        .uri({
          scheme: [/smtps?/, /https?/],
          allowRelative: false,
          relativeOnly: false
        })
        .empty('')
    )
    .empty('')
};

router.get('/', (req, res, next) => {
  apiClient.filters.list(req.user, (err, filters) => {
    if (err) {
      return next(err);
    }
    res.render('account/filters', {
      title: 'Filters',
      activeFilters: true,
      filters: filters.map((filter, i) => ({
        id: filter.id.toString(),
        query: filter.query.map(item => item.filter(val => val).join(': ')).join(', '),
        action: filter.action.map(item => item.filter(val => val).join(': ')).join(', '),
        index: i + 1
      })),
      // csrfToken: req.csrfToken()
    });
  });
});

router.get('/create', (req, res, next) => {
  apiClient.mailboxes.list(req.user, false, (err, mailboxes) => {
    if (err) {
      return next(err);
    }

    res.render('account/filters/create', {
      title: 'Create filter',
      activeFilters: true,
      // csrfToken: req.csrfToken(),
      mailboxes
    });
  });
});

router.get('/edit', (req, res) => {
  const updateSchema = Joi.object().keys({
    id: Joi.string().trim().hex().length(24).label('Filtri ID').required()
  });

  let result = updateSchema.validate(req.query, {
    abortEarly: false,
    convert: true,
    allowUnknown: false
  });

  if (result.error) {
    if (result.error && result.error.details) {
      result.error.details.forEach(detail => {
        req.flash('danger', detail.message);
      });
    }
    return res.redirect('/account/filters');
  }

  apiClient.mailboxes.list(req.user, false, (err, mailboxes) => {
    if (err) {
      req.flash('danger', err.message);
      return res.redirect('/account/filters');
    }
    apiClient.filters.get(req.user, result.value.id, (err, filter) => {
      if (err) {
        req.flash('danger', err.message);
        return res.redirect('/account/filters');
      }

      prepareFilter(filter);

      res.render('account/filters/edit', {
        title: 'Edit filter',
        activeFilters: true,
        // csrfToken: req.csrfToken(),
        mailboxes: mailboxes.map(mailbox => {
          if (filter.action.mailbox) {
            mailbox.selected = mailbox.id === filter.action.mailbox;
          }
          return mailbox;
        }),
        values: filter
      });
    });
  });
});

router.post('/delete', (req, res) => {
  const updateSchema = Joi.object().keys({
    id: Joi.string().trim().hex().length(24).label('Filter ID').required()
  });

  // delete req.body._csrf;
  let result = updateSchema.validate(req.body, {
    abortEarly: false,
    convert: true,
    allowUnknown: false
  });

  if (result.error) {
    if (result.error && result.error.details) {
      result.error.details.forEach(detail => {
        req.flash('danger', detail.message);
      });
    }
    return res.redirect('/account/filters');
  }

  apiClient.filters.del(req.user, result.value.id, err => {
    if (err) {
      req.flash('danger', 'Database Error, failed to update user and delete filter');
      return res.redirect('/account/filters');
    }

    req.flash('success', 'User data updated, filter was deleted');
    return res.redirect('/account/filters');
  });
});

router.post('/create', (req, res, next) => {
  apiClient.mailboxes.list(req.user, false, (err, mailboxes) => {
    if (err) {
      return next(err);
    }

    const createSchema = Joi.object()
      .keys(filterBaseSchema)
      .keys({
        action_mailbox: Joi.string()
          .empty('')
          .valid(...mailboxes.map(mailbox => mailbox.id))
          .label('Move to mailbox')
      });

    // delete req.body._csrf;
    if (req.body.action_targets) {
      req.body.action_targets = req.body.action_targets.split(',');
    }
    let result = createSchema.validate(req.body, {
      abortEarly: false,
      convert: true,
      allowUnknown: false
    });

    let showErrors = (errors, disableDefault) => {
      if (!disableDefault) {
        req.flash('danger', 'Failed to create filter');
      }

      prepareFilter(result.value);

      res.render('account/filters/create', {
        title: 'Create filter',
        values: result.value,
        errors,
        activeFilters: true,
        mailboxes: mailboxes.map(mailbox => {
          mailbox.selected = mailbox.id.toString() === result.value.action.mailbox;
          return mailbox;
        }),
        // csrfToken: req.csrfToken()
      });
    };

    if (result.error) {
      let errors = {};
      if (result.error && result.error.details) {
        result.error.details.forEach(detail => {
          let path = detail.path;
          if (/^query_size/.test(path)) {
            path = 'query_size';
          } else if (/^query_ha/.test(path)) {
            path = 'query_ha';
          }
          if (!errors[path]) {
            errors[path] = detail.message;
          }
        });
      }

      return showErrors(errors);
    }

    apiClient.filters.create(req.user, getFilterObject(result.value), (err, data) => {
      if (err) {
        req.flash('danger', err.message);
        return showErrors(false, true);
      }
      req.flash('success', 'Filter was created');
      return res.redirect('/account/filters?created=' + encodeURIComponent(data.id));
    });
  });
});

router.post('/edit', (req, res, next) => {
  apiClient.mailboxes.list(req.user, false, (err, mailboxes) => {
    if (err) {
      return next(err);
    }

    const createSchema = Joi.object()
      .keys({
        id: Joi.string().trim().hex().length(24).label('Filtri ID').required()
      })
      .keys(filterBaseSchema)
      .keys({
        action_mailbox: Joi.string()
          .empty('')
          .valid(...mailboxes.map(mailbox => mailbox.id))
          .label('Liiguta kausta')
      });

    // delete req.body._csrf;
    if (req.body.action_targets) {
      req.body.action_targets = req.body.action_targets.split(',');
    }
    let result = createSchema.validate(req.body, {
      abortEarly: false,
      convert: true,
      allowUnknown: false
    });

    let showErrors = (errors, disableDefault) => {
      if (!disableDefault) {
        req.flash('danger', 'Filtri muutmine ebaõnnestus');
      }

      prepareFilter(result.value);

      res.render('account/filters/edit', {
        title: 'Muuda filtrit',
        values: result.value,
        errors,
        activeFilters: true,
        mailboxes: mailboxes.map(mailbox => {
          mailbox.selected = mailbox.id.toString() === result.value.action.mailbox;
          return mailbox;
        }),
        // csrfToken: req.csrfToken()
      });
    };

    if (result.error) {
      let errors = {};
      if (result.error && result.error.details) {
        result.error.details.forEach(detail => {
          let path = detail.path;
          if (/^query_size/.test(path)) {
            path = 'query_size';
          } else if (/^query_ha/.test(path)) {
            path = 'query_ha';
          }
          if (!errors[path]) {
            errors[path] = detail.message;
          }
        });
      }

      return showErrors(errors);
    }

    apiClient.filters.update(req.user, result.value.id, getFilterObject(result.value), err => {
      if (err) {
        req.flash('danger', err.message);
        return showErrors(false, true);
      }
      req.flash('success', 'Filter data was updated');
      return res.redirect('/account/filters?updated=' + encodeURIComponent(result.value.id));
    });
  });
});

function prepareFilter(filter) {
  filter.query = filter.query || {};
  filter.action = filter.action || {};

  ['from', 'to', 'subject', 'text', 'listId'].forEach(key => {
    if (key in filter.query) {
      filter['query_' + key] = filter.query[key];
    }
  });

  if ('ha' in filter.query) {
    filter.query_haYes = !!filter.query.ha;
    filter.query_haNo = !filter.query.ha;
  }

  if (filter.query.size) {
    // from actual filter data
    let size = Math.abs(filter.query.size);
    filter.query_sizeTypeGt = filter.query.size > 0;
    filter.query_sizeTypeLt = filter.query.size < 0;
    if (size >= 1024 * 1024 && !(size % (1024 * 1024))) {
      filter.query_sizeUnitMB = true;
      filter.query_sizeValue = Math.round(size / (1024 * 1024));
    } else if (size >= 1024 && !(filter.query.size % 1024)) {
      filter.query_sizeUnitKB = true;
      filter.query_sizeValue = Math.round(size / 1024);
    } else {
      filter.query_sizeUnitB = true;
      filter.query_sizeValue = size;
    }
  } else if (filter.query_sizeValue) {
    // from the form values
    filter.query_sizeTypeGt = filter.query_sizeType === 1;
    filter.query_sizeTypeLt = filter.query_sizeType === -1;

    filter.query_sizeUnitMB = filter.query_sizeUnit === 'MB';
    filter.query_sizeUnitKB = filter.query_sizeUnit === 'kB';
    filter.query_sizeUnitB = filter.query_sizeUnit === 'B';
  }

  ['seen', 'flag', 'delete', 'spam'].forEach(key => {
    if (key in filter.action) {
      filter['action_' + key + 'Yes'] = !!filter.action[key];
      filter['action_' + key + 'No'] = !filter.action[key];
    }
  });

  if (filter.action.targets) {
    filter.action_targets = filter.action.targets.map(targetData => (typeof targetData === 'string' ? targetData : targetData.value)).join(', ');
  }
}

function getFilterObject(data) {
  let filter = {
    query: {},
    action: {}
  };

  // exact values
  ['name', 'query_from', 'query_to', 'query_subject', 'query_listId', 'query_text', 'action_mailbox', 'action_targets'].forEach(key => {
    let parts = key.split('_');
    let keyName = parts.pop();
    let keyPrefix = parts[0] || false;
    let obj = keyPrefix ? filter[keyPrefix] : filter;

    if (key in data) {
      obj[keyName] = data[key];
    } else {
      // unset
      obj[keyName] = '';
    }
  });

  // booleans
  ['query_ha', 'action_seen', 'action_flag', 'action_delete', 'action_spam'].forEach(key => {
    let parts = key.split('_');
    let keyName = parts.pop();
    let keyPrefix = parts[0] || false;
    let obj = keyPrefix ? filter[keyPrefix] : filter;

    if (key + 'Yes' in data) {
      obj[keyName] = true;
    } else if (key + 'No' in data) {
      obj[keyName] = false;
    } else {
      // unset
      obj[keyName] = '';
    }
  });

  // size
  if (data.query_sizeValue) {
    let unit = 1;
    if (data.query_sizeUnit === 'MB') {
      unit = 1024 * 1024;
    } else if (data.query_sizeUnit === 'kB') {
      unit = 1024;
    }
    filter.query.size = data.query_sizeType * data.query_sizeValue * unit;
  }

  return filter;
}

module.exports = router;
