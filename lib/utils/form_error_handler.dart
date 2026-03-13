import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import '../models/server_error.dart';

class FormErrorHandler {
  /// Automatically maps ServerError (FastAPI) to FormBuilder fields
  static void applyErrors({
    required GlobalKey<FormBuilderState> formKey,
    required ServerError error,
    required BuildContext context,
  }) {
    final formState = formKey.currentState;
    bool fieldMapped = false;
    
    if (formState != null && error.fieldErrors != null) {
      error.fieldErrors!.forEach((field, messages) {
        // Attempt to find the field in the form
        if (formState.fields.containsKey(field)) {
          formState.invalidateField(
            name: field,
            errorText: messages.join(', '),
          );
          fieldMapped = true;
        }
      });
    }

    // Show a SnackBar if there are no field-specific errors or if some errors 
    // couldn't be mapped to any visible field.
    if (!fieldMapped || (error.fieldErrors == null || error.fieldErrors!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(error.message)),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}
